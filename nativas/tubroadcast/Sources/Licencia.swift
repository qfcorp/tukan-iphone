// Licencia del Panel Tukán Central (igual que la app Android: core/.../modulos/Licencia.kt).
// El panel la firma con ECDSA P-256 + SHA-256; la app solo trae la llave PÚBLICA, así nadie puede fabricar licencias.
import CryptoKit
import Foundation

/// Llave pública del Panel Tukán Central (https://panel.tukanec.com/tubroadcast_api.php?a=llave).
/// Es la misma que usa Android (app/build.gradle.kts). La privada solo vive en el servidor.
enum LlavePanel {
    static let publica = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEApJ17UKcakXgfJ5L5Zy6j49Jy+3nj0dtX/msn4Vvu8yMebp13VoDO1B7IGsE9YaKewZ7WIMR2P2CpNsTFbN2rw=="
    static let servidor = URL(string: "https://panel.tukanec.com")!
}

/// Módulos que viajan en la licencia (las claves no se cambian nunca; iguales a Modulo.kt y Broadcast.php).
enum Modulo {
    static let rtmp = "rtmp"
    static let srt = "srt"
}

struct Licencia: Codable, Equatable, Sendable {
    var dispositivo: String
    var cliente: String
    var plan: String
    var modulos: [String]
    var emitida: Int64
    var vence: Int64
    /// Cuánto puede funcionar sin hablar con el panel (72 horas).
    var maxSinConexionSeg: Int64 = 72 * 3600
    var demo: Bool = false
    var firma: String = ""

    init(dispositivo: String, cliente: String, plan: String, modulos: [String], emitida: Int64, vence: Int64,
         maxSinConexionSeg: Int64 = 72 * 3600, demo: Bool = false, firma: String = "") {
        self.dispositivo = dispositivo; self.cliente = cliente; self.plan = plan; self.modulos = modulos
        self.emitida = emitida; self.vence = vence; self.maxSinConexionSeg = maxSinConexionSeg; self.demo = demo; self.firma = firma
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dispositivo = try c.decode(String.self, forKey: .dispositivo)
        cliente = try c.decodeIfPresent(String.self, forKey: .cliente) ?? ""
        plan = try c.decodeIfPresent(String.self, forKey: .plan) ?? ""
        modulos = try c.decodeIfPresent([String].self, forKey: .modulos) ?? []
        emitida = try c.decodeIfPresent(Int64.self, forKey: .emitida) ?? 0
        vence = try c.decodeIfPresent(Int64.self, forKey: .vence) ?? 0
        maxSinConexionSeg = try c.decodeIfPresent(Int64.self, forKey: .maxSinConexionSeg) ?? 72 * 3600
        demo = try c.decodeIfPresent(Bool.self, forKey: .demo) ?? false
        firma = try c.decodeIfPresent(String.self, forKey: .firma) ?? ""
    }

    /// Texto exacto que se firma. DEBE ser idéntico al del panel (Broadcast::textoFirmado) y al de Android:
    /// dispositivo|cliente|plan|modulos ordenados separados por coma|emitida|vence|maxSinConexionSeg|demo(1/0)
    var textoFirmado: String {
        let m = modulos.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
        return [dispositivo, cliente, plan, m.joined(separator: ","), String(emitida), String(vence),
                String(maxSinConexionSeg), demo ? "1" : "0"].joined(separator: "|")
    }

    func tiene(_ modulo: String) -> Bool { modulos.contains { $0.lowercased() == modulo } }

    var nombrePlan: String { Licencia.nombrePlan(plan) }

    static func nombrePlan(_ clave: String) -> String {
        switch clave {
        case "basico": return "Básico"
        case "completo": return "Completo"
        case "dia": return "Pase de 24 horas"
        case "a_medida": return "A medida"
        default: return clave
        }
    }
}

enum EstadoLicencia: Equatable {
    /// Sin licencia (o no sirve): la app funciona en modo gratis. El texto explica por qué.
    case gratis(String)
    case valida(Licencia)

    var licencia: Licencia? { if case .valida(let l) = self { return l }; return nil }
    var esValida: Bool { licencia != nil }
}

struct VerificadorLicencia {
    private let llave: P256.Signing.PublicKey?

    init(llavePublicaBase64: String) {
        if let datos = Data(base64Encoded: llavePublicaBase64.trimmingCharacters(in: .whitespacesAndNewlines)) {
            llave = try? P256.Signing.PublicKey(derRepresentation: datos)
        } else {
            llave = nil
        }
    }

    /// La firma del panel (openssl_sign) viene en DER y en base64.
    func firmaCorrecta(_ l: Licencia) -> Bool {
        guard let llave, !l.firma.isEmpty, let bytes = Data(base64Encoded: l.firma),
              let firma = try? P256.Signing.ECDSASignature(derRepresentation: bytes) else { return false }
        return llave.isValidSignature(firma, for: Data(l.textoFirmado.utf8))
    }

    /// - Parameters:
    ///   - ahora: segundos epoch
    ///   - ultimoContacto: segundos epoch de la última vez que el panel respondió
    func verificar(_ l: Licencia?, dispositivo: String, ahora: Int64, ultimoContacto: Int64) -> EstadoLicencia {
        guard let l else { return .gratis("Versión gratis. Activa un plan para transmitir sin límites.") }
        if !firmaCorrecta(l) { return .gratis("La licencia no es válida (firma incorrecta).") }
        if l.dispositivo != dispositivo { return .gratis("La licencia es de otro celular.") }
        if ahora > l.vence { return .gratis(l.plan == "dia" ? "El pase de 24 horas terminó." : "El plan venció. Renueva tu plan.") }
        if ahora - ultimoContacto > l.maxSinConexionSeg { return .gratis("Conéctate a internet para confirmar tu licencia.") }
        return .valida(l)
    }
}
