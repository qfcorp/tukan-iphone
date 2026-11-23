// Compras dentro de la app con Apple (StoreKit 2). Los precios los pone Apple (Product.displayPrice): NUNCA a mano.
// IDs: tubroadcast.basico.N.mes|anio, tubroadcast.completo.N.mes|anio (suscripciones, grupo «TuBroadcast»)
//      tubroadcast.pase24.N (consumible), N = 1, 3, 5 o 10 celulares.
import StoreKit
import SwiftUI

/// Lo que dice el ID de un producto.
struct InfoProducto: Equatable {
    enum Tipo: String { case basico, completo, pase24 }
    enum Periodo: String { case mes, anio, pase }

    let tipo: Tipo
    let celulares: Int
    let periodo: Periodo

    static let celularesPosibles = [1, 3, 5, 10]

    static func de(_ id: String) -> InfoProducto? {
        let p = id.split(separator: ".").map(String.init)
        guard p.count >= 3, p[0] == "tubroadcast", let tipo = Tipo(rawValue: p[1]),
              let n = Int(p[2]), celularesPosibles.contains(n) else { return nil }
        if tipo == .pase24 { return p.count == 3 ? InfoProducto(tipo: .pase24, celulares: n, periodo: .pase) : nil }
        guard p.count == 4, let periodo = Periodo(rawValue: p[3]), periodo != .pase else { return nil }
        return InfoProducto(tipo: tipo, celulares: n, periodo: periodo)
    }

    var id: String {
        tipo == .pase24 ? "tubroadcast.pase24.\(celulares)" : "tubroadcast.\(tipo.rawValue).\(celulares).\(periodo.rawValue)"
    }

    /// Los 20 productos.
    static let todos: [String] = {
        var ids: [String] = []
        for n in celularesPosibles {
            for t in ["basico", "completo"] { for per in ["mes", "anio"] { ids.append("tubroadcast.\(t).\(n).\(per)") } }
            ids.append("tubroadcast.pase24.\(n)")
        }
        return ids
    }()

    var titulo: String {
        switch tipo {
        case .basico: return "Básico"
        case .completo: return "Completo"
        case .pase24: return "Pase de 24 horas"
        }
    }

    var descripcion: String {
        switch tipo {
        case .basico: return "RTMP y RTMPS sin límites: YouTube, Facebook, Kick, Twitch o tu servidor. Hasta 1080p y sin marca de agua."
        case .completo: return "RTMP, RTMPS y SRT sin límites (vMix, OBS y cualquier receptor SRT). Hasta 1080p y sin marca de agua."
        case .pase24: return "Todo sin límites durante 24 horas. Un solo pago, no se renueva."
        }
    }

    var textoPeriodo: String {
        switch periodo {
        case .mes: return "al mes"
        case .anio: return "al año"
        case .pase: return "un solo pago"
        }
    }

    var textoCelulares: String { celulares == 1 ? "1 celular" : "\(celulares) celulares" }

    /// Orden en la pantalla: Básico mes, Básico año, Completo mes, Completo año, Pase.
    var orden: Int {
        switch (tipo, periodo) {
        case (.basico, .mes): return 0
        case (.basico, _): return 1
        case (.completo, .mes): return 2
        case (.completo, _): return 3
        default: return 4
        }
    }
}

enum ResultadoCompra {
    case listo(RespuestaActivacion)
    case cancelada
    case pendiente
    case error(String)
}

@MainActor
final class Tienda: ObservableObject {
    @Published private(set) var productos: [Product] = []
    @Published private(set) var cargando = false
    @Published private(set) var trabajando = false
    @Published var aviso: String?
    /// Última compra registrada en el panel (para mostrar el código del paquete).
    @Published private(set) var ultimaCompra: RespuestaActivacion?

    private let gestor: GestorLicencia
    private var escucha: Task<Void, Never>?

    init(gestor: GestorLicencia) {
        self.gestor = gestor
    }

    func productos(celulares: Int) -> [Product] {
        productos.filter { InfoProducto.de($0.id)?.celulares == celulares }
            .sorted { (InfoProducto.de($0.id)?.orden ?? 9) < (InfoProducto.de($1.id)?.orden ?? 9) }
    }

    func cargarProductos() async {
        cargando = true
        defer { cargando = false }
        do {
            productos = try await Product.products(for: InfoProducto.todos)
            if productos.isEmpty { aviso = "No se pudieron cargar los planes. Revisa tu internet e intenta otra vez." }
        } catch {
            aviso = "No se pudieron cargar los planes: \(error.localizedDescription)"
        }
    }

    /// Compra con Apple. El appAccountToken (UUID del llavero) va en la compra y luego al panel.
    func comprar(_ producto: Product) async -> ResultadoCompra {
        trabajando = true
        defer { trabajando = false }
        do {
            let r = try await producto.purchase(options: [.appAccountToken(gestor.appCuenta)])
            switch r {
            case .success(let verificacion):
                return await procesar(verificacion)
            case .userCancelled:
                return .cancelada
            case .pending:
                return .pendiente
            @unknown default:
                return .error("La compra no se completó.")
            }
        } catch {
            return .error("La compra no se completó: \(error.localizedDescription)")
        }
    }

    /// Manda una transacción verificada al panel y, si el panel la acepta, la termina (finish).
    /// Si no hay internet NO se termina: StoreKit la vuelve a entregar y se reintenta.
    func procesar(_ verificacion: VerificationResult<Transaction>) async -> ResultadoCompra {
        guard case .verified(let t) = verificacion else {
            return .error("Apple no pudo verificar la compra. Intenta otra vez.")
        }
        guard InfoProducto.de(t.productID) != nil else { await t.finish(); return .error("Producto desconocido.") }
        if t.revocationDate != nil { await t.finish(); return .error("Esta compra fue reembolsada o cancelada.") }
        do {
            let r = try await gestor.registrarCompraApple(jws: verificacion.jwsRepresentation)
            if r.ok {
                await t.finish()
                ultimaCompra = r
                return .listo(r)
            }
            return .error(r.mensaje.isEmpty ? "El servidor de Tukán no aceptó la compra." : r.mensaje)
        } catch {
            return .error("Tu pago está hecho, pero no se pudo conectar con el servidor de Tukán. "
                          + "Abre la app con internet y toca «Restaurar compras».")
        }
    }

    /// Restaurar compras: sincroniza con Apple y vuelve a registrar en el panel las compras vigentes.
    func restaurar() async -> String {
        trabajando = true
        defer { trabajando = false }
        do { try await AppStore.sync() } catch {
            return "No se pudo hablar con Apple: \(error.localizedDescription)"
        }
        var ultima: VerificationResult<Transaction>?
        for await v in Transaction.currentEntitlements {
            if case .verified(let t) = v, InfoProducto.de(t.productID) != nil, t.revocationDate == nil {
                if case .verified(let u)? = ultima, u.purchaseDate >= t.purchaseDate { continue }
                ultima = v
            }
        }
        await revisarPendientes()
        guard let ultima else {
            return gestor.estado.esValida ? "Tu licencia está activa." : "No encontramos compras vigentes con esta cuenta de Apple."
        }
        switch await procesar(ultima) {
        case .listo(let r): return r.mensaje.isEmpty ? "Compras restauradas." : r.mensaje
        case .error(let m): return m
        default: return "Compras restauradas."
        }
    }

    /// Compras que quedaron sin terminar (por ejemplo, sin internet al comprar).
    func revisarPendientes() async {
        for await v in Transaction.unfinished {
            _ = await procesar(v)
        }
    }

    /// Renovaciones, compras aprobadas después (Pedir permiso) o hechas en otro equipo.
    func escucharTransacciones() {
        guard escucha == nil else { return }
        escucha = Task { [weak self] in
            for await v in Transaction.updates {
                guard let self else { return }
                _ = await self.procesar(v)
            }
        }
    }

    func gestionarSuscripcion() async {
        guard let escena = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        do { try await AppStore.showManageSubscriptions(in: escena) } catch {
            aviso = "No se pudo abrir la administración de suscripciones: \(error.localizedDescription)"
        }
    }
}
