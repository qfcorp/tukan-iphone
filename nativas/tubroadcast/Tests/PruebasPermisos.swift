// Permisos de cámara/micrófono y textos de error (error real de iPhone 16 Pro Max: "HaishinKit.MediaMixer.Error 0").
import AVFoundation
import HaishinKit
import XCTest
@testable import TuBroadcast

final class PruebasPermisos: XCTestCase {
    func testPasoSegunPermiso() {
        XCTAssertEqual(Permisos.paso(.authorized), .seguir)
        XCTAssertEqual(Permisos.paso(.notDetermined), .pedir)
        XCTAssertEqual(Permisos.paso(.denied), .negado)
        XCTAssertEqual(Permisos.paso(.restricted), .negado)
    }

    func testAvisoDePermisoMuestraBotonAjustes() {
        XCTAssertTrue(Permisos.esAvisoDePermiso(Permisos.avisoSinCamara))
        XCTAssertTrue(Permisos.esAvisoDePermiso(Permisos.avisoSinMicrofono))
        XCTAssertFalse(Permisos.esAvisoDePermiso(Limites.avisoCorte))
        XCTAssertFalse(Permisos.esAvisoDePermiso(nil))
    }

    func testDetalleDesenvuelveElErrorDeHaishinKit() {
        let sinPermiso = NSError(domain: AVFoundationErrorDomain,
                                 code: AVError.Code.applicationIsNotAuthorizedToUseDevice.rawValue)
        XCTAssertEqual(Permisos.detalle(MediaMixer.Error.failedToAttach(sinPermiso)),
                       "falta el permiso en Ajustes del iPhone")
        let ocupada = NSError(domain: AVFoundationErrorDomain,
                              code: AVError.Code.deviceAlreadyUsedByAnotherSession.rawValue)
        XCTAssertTrue(Permisos.detalle(MediaMixer.Error.failedToAttach(ocupada)).contains("otra app"))
        XCTAssertEqual(Permisos.detalle(MediaMixer.Error.deviceNotFound), "no se encontró el dispositivo")
        // Cualquier otro error: muestra el texto, el dominio y el código para poder arreglarlo
        let otro = NSError(domain: "Prueba", code: 42, userInfo: [NSLocalizedDescriptionKey: "algo pasó"])
        XCTAssertEqual(Permisos.detalle(MediaMixer.Error.failedToAttach(otro)), "algo pasó (Prueba 42)")
        XCTAssertFalse(Permisos.detalle(MediaMixer.Error.failedToAttach(otro)).contains("MediaMixer.Error 0"))
    }
}
