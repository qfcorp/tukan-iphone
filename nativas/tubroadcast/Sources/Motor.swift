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

    private var mixer = MediaMixer()
    private var sesion: (any StreamSession)?
    private var vista: MTHKView?
    private var tareas: [Task<Void, Never>] = []
    private var reloj: Timer?
    private var inicio: Date?

    var enVivo: Bool { estado == .open }
    var conectando: Bool { estado == .connecting }

    /// Prende la camara y el microfono (sin transmitir todavia).
    func prenderCamara(_ ajustes: Ajustes) async {
        let posicion: AVCaptureDevice.Position = frontal ? .front : .back
        let camara = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: posicion)
        do {
            try await mixer.attachVideo(camara) { unidad in
                unidad.isVideoMirrored = posicion == .front
            }
            try await mixer.attachAudio(AVCaptureDevice.default(for: .audio))
            try? await mixer.setFrameRate(Float64(ajustes.fps))
        } catch {
            aviso = "No se pudo abrir la camara o el microfono: \(error.localizedDescription)"
        }
        await mixer.startRunning()
        if let vista { await mixer.addOutput(vista) }
        camaraLista = camara != nil
        #if !targetEnvironment(simulator)
        if camara == nil { aviso = "Este equipo no tiene camara disponible." }
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

    /// Empieza a transmitir a la conexion activa.
    func transmitir(_ ajustes: Ajustes) {
        guard let conexion = ajustes.conexionActiva else {
            aviso = "Primero agregue una conexion en Ajustes."
            return
        }
        if let problema = conexion.problema { aviso = problema; return }
        guard let url = conexion.direccionFinal else { aviso = "La direccion no es valida."; return }
        Task {
            do {
                guard let s = try await StreamSessionBuilderFactory.shared.make(url).setMode(.publish).build() else {
                    aviso = "No se pudo preparar la conexion \(conexion.tipo)."
                    return
                }
                sesion = s
                var video = await s.stream.videoSettings
                video.videoSize = ajustes.resolucion.tamano
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
                    Task { @MainActor in self?.aviso = "Se corto la conexion con el destino." }
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
        if let s = sesion {
            await mixer.removeOutput(s.stream)
            try? await s.close()
        }
        sesion = nil
        tareas.forEach { $0.cancel() }
        tareas.removeAll()
        cambioDeEstado(.closed)
    }

    private func cambioDeEstado(_ nuevo: StreamSessionReadyState) {
        estado = nuevo
        switch nuevo {
        case .open:
            UIApplication.shared.isIdleTimerDisabled = true
            inicio = Date()
            reloj?.invalidate()
            reloj = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tic() }
            }
        case .closed:
            UIApplication.shared.isIdleTimerDisabled = false
            reloj?.invalidate(); reloj = nil
            segundos = 0; kbps = 0
        default:
            break
        }
    }

    private func tic() {
        if let inicio { segundos = Int(Date().timeIntervalSince(inicio)) }
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
