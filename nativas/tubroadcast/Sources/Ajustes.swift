import Foundation
import SwiftUI

/// Un destino de transmision: rtmp://, rtmps:// o srt://
struct Conexion: Codable, Identifiable, Equatable {
    var id = UUID()
    var nombre: String
    var url: String
    var clave: String = ""   // stream key (solo RTMP)

    var tipo: String {
        let u = url.lowercased()
        if u.hasPrefix("srt://") { return "SRT" }
        if u.hasPrefix("rtmps://") { return "RTMPS" }
        if u.hasPrefix("rtmp://") { return "RTMP" }
        return "?"
    }

    /// Direccion completa que entiende HaishinKit (RTMP lleva la clave al final).
    var direccionFinal: URL? {
        var texto = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if tipo.hasPrefix("RTMP") && !clave.isEmpty {
            if texto.hasSuffix("/") { texto.removeLast() }
            texto += "/" + clave.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return URL(string: texto)
    }

    /// Explica en palabras simples que esta mal (o nil si esta bien).
    var problema: String? {
        if nombre.trimmingCharacters(in: .whitespaces).isEmpty { return "Ponga un nombre a la conexion." }
        if tipo == "?" { return "La direccion debe empezar con rtmp://, rtmps:// o srt://" }
        guard let u = URL(string: url.trimmingCharacters(in: .whitespaces)), let host = u.host, !host.isEmpty else {
            return "La direccion no tiene servidor (ejemplo: srt://192.168.1.10:9000)."
        }
        if tipo == "SRT" && u.port == nil { return "En SRT falta el puerto (ejemplo: srt://servidor:9000)." }
        return nil
    }
}

enum Resolucion: String, CaseIterable, Identifiable, Codable {
    case p720 = "720p", p1080 = "1080p"
    var id: String { rawValue }
    var tamano: CGSize { self == .p720 ? CGSize(width: 1280, height: 720) : CGSize(width: 1920, height: 1080) }
}

@MainActor
final class Ajustes: ObservableObject {
    @Published var conexiones: [Conexion] = [] { didSet { guardar() } }
    @Published var activa: UUID? { didSet { guardar() } }
    @Published var bitrateKbps: Double = 2500 { didSet { guardar() } }
    @Published var resolucion: Resolucion = .p720 { didSet { guardar() } }
    @Published var fps: Int = 30 { didSet { guardar() } }

    private let llave = "tubroadcast_ajustes_v1"
    private var cargando = false

    private struct Guardado: Codable {
        var conexiones: [Conexion]; var activa: UUID?; var bitrateKbps: Double; var resolucion: Resolucion; var fps: Int
    }

    init() {
        cargando = true
        if let datos = UserDefaults.standard.data(forKey: llave),
           let g = try? JSONDecoder().decode(Guardado.self, from: datos) {
            conexiones = g.conexiones; activa = g.activa; bitrateKbps = g.bitrateKbps; resolucion = g.resolucion; fps = g.fps
        }
        cargando = false
    }

    var conexionActiva: Conexion? { conexiones.first { $0.id == activa } ?? conexiones.first }

    private func guardar() {
        if cargando { return }
        let g = Guardado(conexiones: conexiones, activa: activa, bitrateKbps: bitrateKbps, resolucion: resolucion, fps: fps)
        if let datos = try? JSONEncoder().encode(g) { UserDefaults.standard.set(datos, forKey: llave) }
    }

    /// Lee enlaces de configuracion como los de Larix Grove:
    /// tubroadcast://set/v1?conn[][url]=srt%3A%2F%2F...&conn[][name]=Camara1&conn[][url]=...
    /// Devuelve cuantas conexiones se agregaron.
    func importarEnlace(_ enlace: URL) -> Int {
        guard let partes = URLComponents(url: enlace, resolvingAgainstBaseURL: false) else { return 0 }
        var nuevas: [Conexion] = []
        for item in partes.queryItems ?? [] {
            let valor = item.value ?? ""
            switch item.name {
            case "conn[][url]":
                nuevas.append(Conexion(nombre: "Conexion \(conexiones.count + nuevas.count + 1)", url: valor))
            case "conn[][name]":
                if !nuevas.isEmpty { nuevas[nuevas.count - 1].nombre = valor }
            case "conn[][key]", "conn[][streamid]":
                if !nuevas.isEmpty, item.name == "conn[][key]" { nuevas[nuevas.count - 1].clave = valor }
            case "enc[vid][bitrate]":
                if let b = Double(valor), b > 0 { bitrateKbps = b }
            case "enc[vid][fps]":
                if let f = Int(valor), [24, 25, 30, 50, 60].contains(f) { fps = f }
            case "enc[vid][res]":
                if valor.contains("1080") { resolucion = .p1080 } else if valor.contains("720") { resolucion = .p720 }
            default:
                break
            }
        }
        let validas = nuevas.filter { $0.problema == nil }
        conexiones.append(contentsOf: validas)
        if activa == nil { activa = validas.first?.id }
        return validas.count
    }
}
