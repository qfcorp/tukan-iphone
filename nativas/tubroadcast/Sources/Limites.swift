// Límites de la versión GRATIS (decisión de Dimitry, 23 nov 2026):
//   máximo 720p, marca de agua «TuBroadcast» en el video que sale (y en la vista) y corte a los 5 minutos.
// Con plan: Básico = RTMP/RTMPS sin límites; Completo = RTMP + SRT sin límites; Pase 24 h = todo.
// Si el plan no incluye el protocolo de la conexión (por ejemplo Básico + SRT), esa conexión va con los límites gratis.
import CoreGraphics
import Foundation

/// Reloj que se puede cambiar en las pruebas.
protocol Reloj {
    func ahora() -> Date
}

struct RelojSistema: Reloj {
    func ahora() -> Date { Date() }
}

struct Limites: Equatable {
    /// nil = sin tope.
    var maxResolucion: Resolucion?
    var marcaDeAgua: Bool
    /// nil = sin tope de tiempo.
    var maxSegundos: Int?

    static let gratis = Limites(maxResolucion: .p720, marcaDeAgua: true, maxSegundos: 5 * 60)
    static let sinLimites = Limites(maxResolucion: nil, marcaDeAgua: false, maxSegundos: nil)

    var esGratis: Bool { self != .sinLimites }

    static let textoMarca = "TuBroadcast"
    static let avisoCorte = "La versión gratis transmite hasta 5 minutos. Activa un plan para seguir."

    /// Límites para una conexión según la licencia.
    static func para(tipoConexion: String, estado: EstadoLicencia) -> Limites {
        guard let l = estado.licencia else { return .gratis }
        let modulo = tipoConexion.uppercased() == "SRT" ? Modulo.srt : Modulo.rtmp
        return l.tiene(modulo) ? .sinLimites : .gratis
    }

    /// Resolución que de verdad sale (la versión gratis baja 1080p a 720p).
    func resolucion(pedida: Resolucion) -> Resolucion {
        guard let tope = maxResolucion else { return pedida }
        return pedida.tamano.height > tope.tamano.height ? tope : pedida
    }

    /// Tamaño del video que sale, horizontal o vertical según cómo se tenga el celular.
    func tamanoVideo(pedida: Resolucion, vertical: Bool) -> CGSize {
        let t = resolucion(pedida: pedida).tamano
        return vertical ? CGSize(width: t.height, height: t.width) : t
    }
}

/// Cuenta el tiempo de una transmisión gratis y dice cuándo hay que cortarla.
struct LimiteTiempo {
    let inicio: Date
    let maxSegundos: Int?

    func segundos(_ ahora: Date) -> Int { max(0, Int(ahora.timeIntervalSince(inicio))) }

    func debeCortar(_ ahora: Date) -> Bool {
        guard let maxSegundos else { return false }
        return segundos(ahora) >= maxSegundos
    }

    /// Segundos que quedan (nil si no hay tope).
    func restante(_ ahora: Date) -> Int? {
        guard let maxSegundos else { return nil }
        return max(0, maxSegundos - segundos(ahora))
    }
}
