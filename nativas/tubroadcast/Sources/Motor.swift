import AVFoundation
import HaishinKit
import SwiftUI
import UIKit
import VideoToolbox

/// Camara + microfono -> codificador -> destino (RTMP/RTMPS/SRT), con HaishinKit.
@MainActor
final class Motor: ObservableObject {
    @Published private(set) var estado: StreamSessionReadyState = .closed
    @Published private(set) var camaraLista = false
    @Published private(set) var frontal = false
    @Published private(set) var silencio = false
    @Published private(set) var linterna = false
    @Published private(set) var kbps = 0
    @Published private(set) var segundos = 0
    @Published var aviso: String?
    /// Límites de la transmisión en curso (versión gratis: 720p, marca de agua y 5 minutos).
    @Published private(set) var limitesActuales: Limites = .sinLimites
    /// Segundos que le quedan a una transmisión gratis (nil = sin tope).
    @Published private(set) var restanteGratis: Int?
    /// Reloj de la app (en las pruebas se usa uno falso).
    var reloj: Reloj = RelojSistema()
    private var limiteTiempo: LimiteTiempo?
    static let idMarcaDeAgua = "marca-tubroadcast"

    private var mixer = MediaMixer()
    private var sesion: (any StreamSession)?
    private var vista: MTHKView?
    private var tareas: [Task<Void, Never>] = []
    private var temporizador: Timer?
    private var cerrando = false
    private var inicio: Date?

    var enVivo: Bool { estado == .open }
    var conectando: Bool { estado == .connecting }

    private var prendiendo = false

    /// Prende la camara y el microfono (sin transmitir todavia).
    /// Primero pide los permisos; la camara y el microfono se conectan por separado
    /// para que si uno falla el otro siga, y el aviso dice cual fallo y por que.
    func prenderCamara(_ ajustes: Ajustes) async {
        guard !prendiendo else { return }
        prendiendo = true
        defer { prendiendo = false }
        let posicion: AVCaptureDevice.Position = frontal ? .front : .back
        let camara = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: posicion)
        var problemas: [String] = []
        #if !targetEnvironment(simulator)
        let conCamara = await Permisos.conceder(.video)
        let conMicro = await Permisos.conceder(.audio)
        if !conCamara { aviso = Permisos.avisoSinCamara }
        else if !conMicro { aviso = Permisos.avisoSinMicrofono }
        #else
        let conCamara = true, conMicro = true
        #endif
        Permisos.prepararAudio()
        if conCamara {
            do {
                try await mixer.attachVideo(camara) { unidad in
                    unidad.isVideoMirrored = posicion == .front
                }
                try? await mixer.setFrameRate(Float64(ajustes.fps))
            } catch {
                problemas.append("cámara: \(Permisos.detalle(error))")
            }
        }
        if conMicro {
            do {
                try await mixer.attachAudio(AVCaptureDevice.default(for: .audio))
            } catch {
                problemas.append("micrófono: \(Permisos.detalle(error))")
            }
        }
        if !problemas.isEmpty, aviso == nil {
            aviso = "No se pudo abrir " + problemas.joined(separator: " · ")
        }
        await mixer.startRunning()
        if let vista { await mixer.addOutput(vista) }
        camaraLista = conCamara && camara != nil && problemas.allSatisfy { !$0.hasPrefix("cámara") }
        #if !targetEnvironment(simulator)
        if camara == nil, aviso == nil { aviso = "Este equipo no tiene cámara disponible." }
        #endif
    }

    func cambiarCamara(_ ajustes: Ajustes) {
        frontal.toggle()
        Task { await prenderCamara(ajustes) }
    }

    func alternarSilencio() {
        silencio.toggle()
        let callado = silencio
        Task {
            var s = await mixer.audioMixerSettings
            var pista = s.tracks[0] ?? .init()
            pista.isMuted = callado
            s.tracks[0] = pista
            await mixer.setAudioMixerSettings(s)
        }
    }

    func alternarLinterna() {
        linterna.toggle()
        let prender = linterna
        Task { await mixer.setTorchEnabled(prender) }
    }

    /// Empieza a transmitir a la conexion activa, con los limites de la licencia (gratis o plan).
    func transmitir(_ ajustes: Ajustes, limites: Limites) {
        guard let conexion = ajustes.conexionActiva else {
            aviso = "Primero agregue una conexión en Ajustes."
            return
        }
        if let problema = conexion.problema { aviso = problema; return }
        guard let url = conexion.direccionFinal else { aviso = "La dirección no es válida."; return }
        let orientacion = Motor.orientacionActual()
        let vertical = orientacion == .portrait || orientacion == .portraitUpsideDown
        let tamano = limites.tamanoVideo(pedida: ajustes.resolucion, vertical: vertical)
        limitesActuales = limites
        Task {
            do {
                await mixer.setVideoOrientation(orientacion)
                await ponerMarcaDeAgua(limites.marcaDeAgua, tamano: tamano)
                guard let s = try await StreamSessionBuilderFactory.shared.make(url).setMode(.publish).build() else {
                    aviso = "No se pudo preparar la conexión \(conexion.tipo)."
                    return
                }
                sesion = s
                var video = await s.stream.videoSettings
                video.videoSize = tamano
                video.bitRate = Int(ajustes.bitrateKbps * 1000)
                video.profileLevel = kVTProfileLevel_H264_High_AutoLevel as String
                video.expectedFrameRate = Double(ajustes.fps)
                try await s.stream.setVideoSettings(video)
                await mixer.addOutput(s.stream)
                tareas.append(Task { [weak self] in
                    for await e in await s.readyState {
                        self?.cambioDeEstado(e)
                    }
                })
                try await s.connect { [weak self] in
                    Task { @MainActor in
                        guard let self, !self.cerrando, self.sesion != nil, self.aviso == nil else { return }
                        self.aviso = "Se cortó la conexión con el destino."
                    }
                }
            } catch {
                aviso = "No se pudo conectar: \(error.localizedDescription)"
                await detenerSesion()
            }
        }
    }

    func detener() {
        Task { await detenerSesion() }
    }

    private func detenerSesion() async {
        cerrando = true
        defer { cerrando = false }
        if let s = sesion {
            await mixer.removeOutput(s.stream)
            try? await s.close()
        }
        sesion = nil
        tareas.forEach { $0.cancel() }
        tareas.removeAll()
        cambioDeEstado(.closed)
        if limitesActuales.marcaDeAgua { await ponerMarcaDeAgua(false, tamano: .zero) }
        limitesActuales = .sinLimites
    }

    /// Marca de agua «TuBroadcast» quemada en el video que sale (versión gratis).
    /// Para dibujarla, el mezclador pasa a modo «offscreen» (compone cámara + texto); con plan queda en «passthrough».
    private func ponerMarcaDeAgua(_ activa: Bool, tamano: CGSize) async {
        var mezcla = await mixer.videoMixerSettings
        mezcla.mode = activa ? .offscreen : .passthrough
        await mixer.setVideoMixerSettings(mezcla)
        let mixer = self.mixer
        let id = Motor.idMarcaDeAgua
        await Task { @ScreenActor in
            if activa { await mixer.screen.size = tamano }
            if let marca = await mixer.screen.findById(id) {
                marca.isVisible = activa
                return
            }
            guard activa else { return }
            let texto = TextScreenObject(id: id)
            texto.string = Limites.textoMarca
            let alto = max(24, min(tamano.width, tamano.height) * 0.07)
            texto.attributes = [.font: UIFont.boldSystemFont(ofSize: alto),
                                .foregroundColor: UIColor.white.withAlphaComponent(0.8)]
            texto.horizontalAlignment = .right
            texto.verticalAlignment = .bottom
            texto.layoutMargin = .init(top: 0, left: 0, bottom: alto * 0.8, right: alto * 0.8)
            try? await mixer.screen.addChild(texto)
        }.value
    }

    /// Orientación de la pantalla para girar el video (vertical u horizontal).
    static func orientacionActual() -> AVCaptureVideoOrientation {
        let escena = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        switch escena?.effectiveGeometry.interfaceOrientation {
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }

    private func cambioDeEstado(_ nuevo: StreamSessionReadyState) {
        estado = nuevo
        switch nuevo {
        case .open:
            UIApplication.shared.isIdleTimerDisabled = true
            empezarConteo(limites: limitesActuales)
            temporizador?.invalidate()
            temporizador = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tic() }
            }
        case .closed:
            UIApplication.shared.isIdleTimerDisabled = false
            temporizador?.invalidate(); temporizador = nil
            segundos = 0; kbps = 0
            limiteTiempo = nil; restanteGratis = nil
        default:
            break
        }
    }

    /// Empieza a contar el tiempo en vivo (y el tope de 5 minutos si es la versión gratis).
    func empezarConteo(limites: Limites) {
        limitesActuales = limites
        inicio = reloj.ahora()
        limiteTiempo = LimiteTiempo(inicio: reloj.ahora(), maxSegundos: limites.maxSegundos)
        restanteGratis = limites.maxSegundos
    }

    /// Cada segundo: actualiza el reloj en pantalla y corta la versión gratis a los 5 minutos.
    func tic() {
        let ahora = reloj.ahora()
        if let inicio { segundos = Int(ahora.timeIntervalSince(inicio)) }
        if let limiteTiempo {
            restanteGratis = limiteTiempo.restante(ahora)
            if limiteTiempo.debeCortar(ahora) { cortarPorLimiteGratis() }
        }
    }

    /// La versión gratis transmite hasta 5 minutos: se corta sola con un aviso claro.
    private func cortarPorLimiteGratis() {
        limiteTiempo = nil
        aviso = Limites.avisoCorte
        detener()
    }

    /// Estado para el latido con el panel.
    var estadisticas: Estadisticas {
        Estadisticas(transmitiendo: enVivo, bitrateKbps: kbps, segundosEnVivo: segundos,
                     camara: frontal ? "frontal" : "trasera", silenciado: silencio)
    }

    var tiempoTexto: String {
        String(format: "%02d:%02d:%02d", segundos / 3600, (segundos / 60) % 60, segundos % 60)
    }
}

extension Motor: MTHKViewRepresentable.PreviewSource {
    nonisolated func connect(to view: MTHKView) {
        Task { @MainActor in
            self.vista = view
            await self.mixer.addOutput(view)
        }
    }
}
