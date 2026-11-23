// Licencia del celular: activar con código, compra de Apple, liberar y latido con el Panel Tukán Central.
// Igual que Android (datos/Almacen.kt y tuner/ServicioTuner.kt): latido cada 30 s con licencia;
// sin internet la licencia firmada vale hasta 72 h desde el último contacto con el panel.
import Foundation
import UIKit

/// Datos del paquete comprado con Apple (para compartir el código con los otros celulares).
struct Paquete: Codable, Equatable {
    var codigo: String
    var plan: String
    var celulares: Int
    var expira: String?
}

@MainActor
final class GestorLicencia: ObservableObject {
    @Published private(set) var estado: EstadoLicencia = .gratis("")
    @Published private(set) var paquete: Paquete?
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

    init(panel: PanelCliente = PanelCliente(), almacen: Almacen = AlmacenLlavero(),
         llavePublica: String = LlavePanel.publica, reloj: Reloj = RelojSistema()) {
        self.panel = panel
        self.almacen = almacen
        self.verificador = VerificadorLicencia(llavePublicaBase64: llavePublica)
        self.reloj = reloj
        if let p = almacen.leer("paquete"), let d = p.data(using: .utf8) {
            paquete = try? JSONDecoder().decode(Paquete.self, from: d)
        }
        recalcular()
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

    var token: String { almacen.leer("token") ?? "" }
    var tieneToken: Bool { !token.isEmpty }

    private var ahoraSeg: Int64 { Int64(reloj.ahora().timeIntervalSince1970) }

    private var licenciaGuardada: Licencia? {
        guard let t = almacen.leer("licencia"), let d = t.data(using: .utf8) else { return nil }
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

    private func guardarPaquete(_ p: Paquete?) {
        paquete = p
        if let p, let d = try? JSONEncoder().encode(p) { almacen.guardar(String(data: d, encoding: .utf8), "paquete") }
        else { almacen.guardar(nil, "paquete") }
    }

    /// Vuelve a modo gratis (al liberar, o si el panel dice que el celular ya no está activado).
    func borrarLicencia() {
        almacen.guardar(nil, "licencia")
        almacen.guardar(nil, "token")
        almacen.guardar(nil, "ultimo_contacto")
        guardarPaquete(nil)
        recalcular()
    }

    func recalcular() {
        let ultimo = Int64(almacen.leer("ultimo_contacto") ?? "") ?? 0
        estado = verificador.verificar(licenciaGuardada, dispositivo: dispositivo, ahora: ahoraSeg, ultimoContacto: ultimo)
    }

    func limites(tipoConexion: String) -> Limites {
        Limites.para(tipoConexion: tipoConexion, estado: estado)
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

    // MARK: - Activar con código (clientes que pagaron por fuera o los otros celulares de un paquete)

    /// Devuelve (ok, mensaje para mostrar).
    func activar(codigo: String) async -> (Bool, String) {
        let limpio = codigo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return (false, "Escribe tu código (por ejemplo TB-ABCD-EFGH).") }
        let pedido = PedidoActivar(codigo: limpio, dispositivo: dispositivo, modelo: Self.modelo, versionApp: Self.versionApp)
        do {
            let (_, r) = try await panel.enviar("activar", pedido, como: RespuestaActivacion.self)
            return aplicar(r, codigoUsado: limpio)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Compra con Apple

    /// Manda la transacción (JWS) al panel. Devuelve la respuesta o lanza error si no hubo conexión.
    func registrarCompraApple(jws: String) async throws -> RespuestaActivacion {
        let pedido = PedidoCompraApple(dispositivo: dispositivo, modelo: Self.modelo, version: Self.versionApp,
                                       transaccion: jws, app_cuenta: appCuenta.uuidString.lowercased(),
                                       versionApp: Self.versionApp)
        let (_, r) = try await panel.enviar("apple_compra", pedido, como: RespuestaActivacion.self)
        if r.ok, r.licencia != nil, !r.token.isEmpty {
            _ = aplicar(r, codigoUsado: nil)
            if let codigo = r.codigo, !codigo.isEmpty {
                guardarPaquete(Paquete(codigo: codigo, plan: r.plan ?? r.licencia?.plan ?? "",
                                       celulares: r.celulares ?? 1, expira: r.expira))
            }
        }
        return r
    }

    /// Guarda licencia y token si la respuesta es buena y la firma sirve para este celular.
    private func aplicar(_ r: RespuestaActivacion, codigoUsado: String?) -> (Bool, String) {
        guard r.ok, let l = r.licencia, !r.token.isEmpty else {
            return (false, r.mensaje.isEmpty ? "No se pudo activar. Intenta otra vez." : r.mensaje)
        }
        if case .gratis(let motivo) = verificador.verificar(l, dispositivo: dispositivo, ahora: ahoraSeg, ultimoContacto: ahoraSeg) {
            return (false, motivo)
        }
        almacen.guardar(r.token, "token")
        guardarLicencia(l)
        if codigoUsado != nil, paquete != nil, paquete?.codigo != codigoUsado { guardarPaquete(nil) }
        return (true, r.mensaje.isEmpty ? "¡Listo! Licencia activada." : r.mensaje)
    }

    // MARK: - Liberar este celular

    /// Devuelve (ok, mensaje). Si el panel responde 429 se muestra su mensaje tal cual.
    func liberar() async -> (Bool, String) {
        guard tieneToken else { return (false, "Este celular no tiene una licencia activa.") }
        do {
            let (codigo, r) = try await panel.enviar("liberar", PedidoLiberar(dispositivo: dispositivo, token: token),
                                                     como: RespuestaLiberar.self)
            if codigo == 429 {
                return (false, r.mensaje.isEmpty ? "Ya no quedan cambios de celular por ahora." : r.mensaje)
            }
            guard r.ok else { return (false, r.mensaje.isEmpty ? "No se pudo liberar este celular." : r.mensaje) }
            borrarLicencia()
            var texto = r.mensaje.isEmpty ? "Listo. Este celular quedó libre y volvió a la versión gratis." : r.mensaje
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
            let (codigo, r) = try await panel.enviar("latido", pedido, como: RespuestaLatido.self)
            if codigo == 401 {
                borrarLicencia()
                mensaje = r.mensaje.isEmpty ? "Este celular ya no está activado. Volvió a la versión gratis." : r.mensaje
                return
            }
            if r.ok {
                if let l = r.licencia { guardarLicencia(l) } else { marcarContacto() }
                if !r.mensaje.isEmpty && r.mensaje != ultimoMensaje { mensaje = r.mensaje }
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
