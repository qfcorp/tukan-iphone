// Licencia del celular: compra de Apple, liberar y latido con el Panel Tukán Central.
// En iPhone el plan se desbloquea SOLO con In-App Purchase (StoreKit 2): no existe forma de escribir o pegar
// un código de activación ni un token (regla 3.1.1 de Apple; revisión del 27 nov 2026). El token y la licencia
// solo llegan del panel como respuesta a una transacción de Apple verificada (apple_compra).
// Igual que Android (datos/Almacen.kt y tuner/ServicioTuner.kt): latido cada 30 s con licencia;
// sin internet la licencia firmada vale hasta 72 h desde el último contacto con el panel.
import Foundation
import UIKit

@MainActor
final class GestorLicencia: ObservableObject {
    @Published private(set) var estado: EstadoLicencia = .gratis("")
    /// Mensaje del panel para mostrar una vez (por ejemplo «Al pase le queda menos de una hora»).
    @Published var mensaje: String?

    let panel: PanelCliente
    private let almacen: Almacen
    private let verificador: VerificadorLicencia
    private let reloj: Reloj
    private var latidos: Task<Void, Never>?
    private var ultimoMensaje = ""
    /// Lo pone el Motor para mandar el estado en el latido.
    var estadisticas: @MainActor () -> Estadisticas = { Estadisticas() }

    static let segundosLatido: UInt64 = 30

    /// Marca que se guarda junto al token cuando la licencia vino de una compra de Apple.
    static let claveOrigen = "origen"
    static let origenApple = "apple"
    /// Datos que guardaban versiones anteriores (código del paquete). Se borran al abrir.
    static let clavesViejas = ["paquete"]

    init(panel: PanelCliente = PanelCliente(), almacen: Almacen = AlmacenLlavero(),
         llavePublica: String = LlavePanel.publica, reloj: Reloj = RelojSistema()) {
        self.panel = panel
        self.almacen = almacen
        self.verificador = VerificadorLicencia(llavePublicaBase64: llavePublica)
        self.reloj = reloj
        olvidarLicenciasQueNoSonDeApple()
        recalcular()
    }

    /// En iPhone solo vale la compra de Apple: si quedó guardado un token o una licencia de antes que no vino
    /// de una compra de Apple (por ejemplo, activados con un código en una versión de prueba), se borran y la app
    /// queda gratis hasta que el usuario compre o toque «Restaurar compras».
    private func olvidarLicenciasQueNoSonDeApple() {
        for clave in Self.clavesViejas where almacen.leer(clave) != nil { almacen.guardar(nil, clave) }
        guard almacen.leer(Self.claveOrigen) != Self.origenApple else { return }
        for clave in ["licencia", "token", "ultimo_contacto", Self.claveOrigen] where almacen.leer(clave) != nil {
            almacen.guardar(nil, clave)
        }
    }

    // MARK: - Datos guardados

    /// Id propio del celular (UUID en el llavero). No es el IDFA.
    var dispositivo: String {
        if let d = almacen.leer("dispositivo"), !d.isEmpty { return d }
        let nuevo = UUID().uuidString
        almacen.guardar(nuevo, "dispositivo")
        return nuevo
    }

    /// appAccountToken para las compras de Apple (UUID en el llavero).
    var appCuenta: UUID {
        if let t = almacen.leer("app_cuenta"), let u = UUID(uuidString: t) { return u }
        let nuevo = UUID()
        almacen.guardar(nuevo.uuidString, "app_cuenta")
        return nuevo
    }

    private var deCompraApple: Bool { almacen.leer(Self.claveOrigen) == Self.origenApple }

    /// Token que entregó el panel después de una compra de Apple (el usuario nunca lo ve ni lo escribe).
    var token: String { deCompraApple ? (almacen.leer("token") ?? "") : "" }
    var tieneToken: Bool { !token.isEmpty }

    private var ahoraSeg: Int64 { Int64(reloj.ahora().timeIntervalSince1970) }

    private var licenciaGuardada: Licencia? {
        guard deCompraApple, let t = almacen.leer("licencia"), let d = t.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Licencia.self, from: d)
    }

    private func guardarLicencia(_ l: Licencia) {
        if let d = try? JSONEncoder().encode(l) { almacen.guardar(String(data: d, encoding: .utf8), "licencia") }
        marcarContacto()
    }

    private func marcarContacto() {
        almacen.guardar(String(ahoraSeg), "ultimo_contacto")
        recalcular()
    }

    /// Vuelve a modo gratis (al liberar, o si el panel dice que el celular ya no está activado).
    func borrarLicencia() {
        almacen.guardar(nil, "licencia")
        almacen.guardar(nil, "token")
        almacen.guardar(nil, "ultimo_contacto")
        almacen.guardar(nil, Self.claveOrigen)
        recalcular()
    }

    func recalcular() {
        let ultimo = Int64(almacen.leer("ultimo_contacto") ?? "") ?? 0
        estado = verificador.verificar(licenciaGuardada, dispositivo: dispositivo, ahora: ahoraSeg, ultimoContacto: ultimo)
    }

    func limites(tipoConexion: String) -> Limites {
        Limites.para(tipoConexion: tipoConexion, estado: estado)
    }

    /// Los textos del panel son los mismos para Android y la web y a veces nombran el código del paquete
    /// de activación. En iPhone no se muestra ningún código: se quitan esas frases y, si no queda nada, va `siVacio`.
    static func textoParaIPhone(_ texto: String, siVacio: String) -> String {
        let frases = texto.components(separatedBy: CharacterSet(charactersIn: ".\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let buenas = frases.filter { f in
            let m = f.lowercased()
            return !m.contains("tb-") && !m.contains("código") && !m.contains("codigo")
        }
        guard !buenas.isEmpty else { return siVacio }
        return buenas.joined(separator: ". ") + "."
    }

    // MARK: - Datos del equipo

    static var modelo: String {
        var u = utsname()
        uname(&u)
        let maquina = withUnsafePointer(to: &u.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return maquina.isEmpty ? "iPhone" : maquina
    }

    static var versionApp: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let c = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "ios-\(v)(\(c))"
    }

    // MARK: - Compra con Apple (la ÚNICA forma de tener un plan en iPhone)

    /// Manda la transacción (JWS) al panel. Devuelve la respuesta (con un mensaje apto para mostrar)
    /// o lanza error si no hubo conexión.
    func registrarCompraApple(jws: String) async throws -> RespuestaCompra {
        let pedido = PedidoCompraApple(dispositivo: dispositivo, modelo: Self.modelo, version: Self.versionApp,
                                       transaccion: jws, app_cuenta: appCuenta.uuidString.lowercased(),
                                       versionApp: Self.versionApp)
        var (_, r) = try await panel.enviar("apple_compra", pedido, como: RespuestaCompra.self)
        guard r.ok, let l = r.licencia, !r.token.isEmpty else {
            r.ok = false
            r.mensaje = Self.textoParaIPhone(r.mensaje, siVacio: "El servidor de Tukán no aceptó la compra. Intenta otra vez.")
            return r
        }
        if case .gratis(let motivo) = verificador.verificar(l, dispositivo: dispositivo, ahora: ahoraSeg, ultimoContacto: ahoraSeg) {
            r.ok = false
            r.mensaje = motivo
            return r
        }
        almacen.guardar(Self.origenApple, Self.claveOrigen)
        almacen.guardar(r.token, "token")
        guardarLicencia(l)
        r.mensaje = "¡Listo! \(l.plan == "dia" ? "" : "Plan ")\(l.nombrePlan) activo en este iPhone."
        return r
    }

    // MARK: - Liberar este celular

    /// Devuelve (ok, mensaje). Si el panel responde 429 se muestra su mensaje tal cual.
    func liberar() async -> (Bool, String) {
        guard tieneToken else { return (false, "Este celular no tiene una licencia activa.") }
        do {
            let (http, r) = try await panel.enviar("liberar", PedidoLiberar(dispositivo: dispositivo, token: token),
                                                   como: RespuestaLiberar.self)
            if http == 429 {
                return (false, Self.textoParaIPhone(r.mensaje, siVacio: "Ya no quedan cambios de celular por ahora."))
            }
            if http == 401 {
                // El panel ya no reconoce este celular: queda libre igual (vuelve a la versión gratis).
                borrarLicencia()
                return (true, Self.textoParaIPhone(r.mensaje, siVacio: "Este celular ya no estaba activado. Volvió a la versión gratis."))
            }
            guard r.ok else { return (false, Self.textoParaIPhone(r.mensaje, siVacio: "No se pudo liberar este celular.")) }
            borrarLicencia()
            // Texto propio: el del panel nombra el código del paquete, que en iPhone no se usa.
            var texto = "Listo. Este celular quedó libre y volvió a la versión gratis. "
                + "Para usar el plan en otro iPhone, abre TuBroadcast allí con la misma cuenta de Apple y toca «Restaurar compras»."
            if let n = r.cambios_restantes { texto += "\nCambios de celular que te quedan: \(n)." }
            return (true, texto)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Latido

    func latido() async {
        guard tieneToken else { recalcular(); return }
        let pedido = PedidoLatido(dispositivo: dispositivo, token: token, controlCedido: false, versionAjustes: 0,
                                  estadisticas: estadisticas())
        do {
            let (http, r) = try await panel.enviar("latido", pedido, como: RespuestaLatido.self)
            if http == 401 {
                borrarLicencia()
                mensaje = "Este celular ya no está activado. Volvió a la versión gratis."
                return
            }
            if r.ok {
                if let l = r.licencia { guardarLicencia(l) } else { marcarContacto() }
                let texto = Self.textoParaIPhone(r.mensaje, siVacio: "")
                if !texto.isEmpty && r.mensaje != ultimoMensaje { mensaje = texto }
                ultimoMensaje = r.mensaje
            }
        } catch {
            // Sin internet: la licencia firmada sigue valiendo hasta 72 h desde el último contacto.
            recalcular()
        }
    }

    func empezarLatidos() {
        guard latidos == nil else { return }
        latidos = Task { [weak self] in
            while !Task.isCancelled {
                await self?.latido()
                try? await Task.sleep(nanoseconds: GestorLicencia.segundosLatido * 1_000_000_000)
            }
        }
    }

    func pararLatidos() {
        latidos?.cancel()
        latidos = nil
    }
}
