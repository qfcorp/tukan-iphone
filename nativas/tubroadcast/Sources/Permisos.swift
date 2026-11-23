// Permisos de cámara y micrófono + sesión de audio del iPhone.
// HaishinKit pide configurar y activar AVAudioSession antes de usar el micrófono (ver su README).
import AVFoundation
import HaishinKit
import UIKit

enum Permisos {
    static let avisoSinCamara = "TuBroadcast no tiene permiso para usar la cámara. Ábrelo en Ajustes del iPhone → TuBroadcast → Cámara."
    static let avisoSinMicrofono = "TuBroadcast no tiene permiso para usar el micrófono. Ábrelo en Ajustes del iPhone → TuBroadcast → Micrófono."

    /// true si el aviso es de permisos (para mostrar el botón «Abrir Ajustes»).
    static func esAvisoDePermiso(_ aviso: String?) -> Bool {
        aviso == avisoSinCamara || aviso == avisoSinMicrofono
    }

    /// Qué hacer según el estado del permiso: pedirlo, seguir o avisar.
    enum Paso: Equatable { case pedir, seguir, negado }

    static func paso(_ estado: AVAuthorizationStatus) -> Paso {
        switch estado {
        case .authorized: return .seguir
        case .notDetermined: return .pedir
        default: return .negado // .denied o .restricted
        }
    }

    /// Pide (si hace falta) el permiso y devuelve si quedó concedido.
    static func conceder(_ tipo: AVMediaType) async -> Bool {
        switch paso(AVCaptureDevice.authorizationStatus(for: tipo)) {
        case .seguir: return true
        case .negado: return false
        case .pedir: return await AVCaptureDevice.requestAccess(for: tipo)
        }
    }

    /// Prepara la sesión de audio para grabar y transmitir (altavoz por defecto).
    static func prepararAudio() {
        let sesion = AVAudioSession.sharedInstance()
        do {
            try sesion.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try sesion.setActive(true)
        } catch {
            // Si falla, la cámara sigue funcionando; el micrófono avisará al conectarse.
        }
    }

    @MainActor static func abrirAjustes() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// Texto claro del error real (HaishinKit envuelve el error de iOS en failedToAttach).
    static func detalle(_ error: Error) -> String {
        if let e = error as? MediaMixer.Error {
            switch e {
            case .failedToAttach(let interno): return detalle(interno)
            case .deviceNotFound: return "no se encontró el dispositivo"
            }
        }
        let ns = error as NSError
        if ns.domain == AVFoundationErrorDomain,
           ns.code == AVError.Code.applicationIsNotAuthorizedToUseDevice.rawValue {
            return "falta el permiso en Ajustes del iPhone"
        }
        if ns.domain == AVFoundationErrorDomain,
           ns.code == AVError.Code.deviceAlreadyUsedByAnotherSession.rawValue {
            return "otra app está usando la cámara o el micrófono; ciérrala e intenta de nuevo"
        }
        return "\(ns.localizedDescription) (\(ns.domain) \(ns.code))"
    }
}
