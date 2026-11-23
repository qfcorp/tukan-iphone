// Dónde se guardan el id del celular, el token, la licencia y el appAccountToken: en el llavero (Keychain) del iPhone.
// El id del celular es un UUID propio (NO es el IDFA ni nada de publicidad).
import Foundation
import Security

protocol Almacen: AnyObject {
    func leer(_ clave: String) -> String?
    func guardar(_ valor: String?, _ clave: String)
}

/// Llavero del iPhone (queda solo en este equipo; no pasa a otro iPhone por copia de seguridad).
/// Si el llavero no está disponible (simulador sin firma), usa UserDefaults para no romper la app.
final class AlmacenLlavero: Almacen {
    private let servicio: String
    private let respaldo = UserDefaults.standard

    init(servicio: String = "com.tukansoftware.tubroadcast.licencia") { self.servicio = servicio }

    private func base(_ clave: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: servicio,
         kSecAttrAccount as String: clave]
    }

    func leer(_ clave: String) -> String? {
        var q = base(clave)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var dato: AnyObject?
        if SecItemCopyMatching(q as CFDictionary, &dato) == errSecSuccess, let d = dato as? Data {
            return String(data: d, encoding: .utf8)
        }
        return respaldo.string(forKey: servicio + "." + clave)
    }

    func guardar(_ valor: String?, _ clave: String) {
        SecItemDelete(base(clave) as CFDictionary)
        respaldo.removeObject(forKey: servicio + "." + clave)
        guard let valor else { return }
        var q = base(clave)
        q[kSecValueData as String] = Data(valor.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if SecItemAdd(q as CFDictionary, nil) != errSecSuccess {
            respaldo.set(valor, forKey: servicio + "." + clave)
        }
    }
}

/// Para las pruebas.
final class AlmacenMemoria: Almacen {
    private var datos: [String: String] = [:]
    init() {}
    func leer(_ clave: String) -> String? { datos[clave] }
    func guardar(_ valor: String?, _ clave: String) { datos[clave] = valor }
}
