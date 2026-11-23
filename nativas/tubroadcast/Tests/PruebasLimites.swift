// Límites de la versión gratis: 720p, marca de agua y corte a los 5 minutos (con reloj falso).
import XCTest
@testable import TuBroadcast

final class PruebasLimites: XCTestCase {
    func lic(_ plan: String, _ modulos: [String]) -> EstadoLicencia {
        .valida(Licencia(dispositivo: "cel", cliente: "c", plan: plan, modulos: modulos, emitida: 0, vence: 1))
    }

    func testSinPlanEsGratisEnRTMPyEnSRT() {
        XCTAssertEqual(Limites.para(tipoConexion: "RTMP", estado: .gratis("")), .gratis)
        XCTAssertEqual(Limites.para(tipoConexion: "RTMPS", estado: .gratis("")), .gratis)
        XCTAssertEqual(Limites.para(tipoConexion: "SRT", estado: .gratis("")), .gratis)
    }

    func testGratisMaximo720p() {
        let g = Limites.gratis
        XCTAssertEqual(g.resolucion(pedida: .p1080), .p720)
        XCTAssertEqual(g.resolucion(pedida: .p720), .p720)
        XCTAssertEqual(g.tamanoVideo(pedida: .p1080, vertical: false), CGSize(width: 1280, height: 720))
        XCTAssertEqual(g.tamanoVideo(pedida: .p1080, vertical: true), CGSize(width: 720, height: 1280))
    }

    func testGratisLlevaMarcaDeAgua() {
        XCTAssertTrue(Limites.gratis.marcaDeAgua)
        XCTAssertEqual(Limites.textoMarca, "TuBroadcast")
        XCTAssertFalse(Limites.sinLimites.marcaDeAgua)
    }

    func testGratisCortaALos5Minutos() {
        XCTAssertEqual(Limites.gratis.maxSegundos, 300)
        XCTAssertEqual(Limites.avisoCorte, "La versión gratis transmite hasta 5 minutos. Activa un plan para seguir.")
        let reloj = RelojFalso()
        let t = LimiteTiempo(inicio: reloj.ahora(), maxSegundos: Limites.gratis.maxSegundos)
        reloj.avanzar(299)
        XCTAssertFalse(t.debeCortar(reloj.ahora()))
        XCTAssertEqual(t.restante(reloj.ahora()), 1)
        reloj.avanzar(1)
        XCTAssertTrue(t.debeCortar(reloj.ahora()))
        XCTAssertEqual(t.restante(reloj.ahora()), 0)
    }

    func testConPlanNoHayTopeDeTiempo() {
        let reloj = RelojFalso()
        let t = LimiteTiempo(inicio: reloj.ahora(), maxSegundos: Limites.sinLimites.maxSegundos)
        reloj.avanzar(10 * 3600)
        XCTAssertFalse(t.debeCortar(reloj.ahora()))
        XCTAssertNil(t.restante(reloj.ahora()))
    }

    func testBasicoEsRTMPsinLimitesPeroSRTconLimites() {
        let basico = lic("basico", ["rtmp", "abr", "grove"])
        XCTAssertEqual(Limites.para(tipoConexion: "RTMP", estado: basico), .sinLimites)
        XCTAssertEqual(Limites.para(tipoConexion: "RTMPS", estado: basico), .sinLimites)
        XCTAssertEqual(Limites.para(tipoConexion: "SRT", estado: basico), .gratis)
        XCTAssertEqual(Limites.sinLimites.resolucion(pedida: .p1080), .p1080)
    }

    func testCompletoYPaseSinLimites() {
        for e in [lic("completo", ["rtmp", "srt", "abr"]), lic("dia", ["rtmp", "srt", "tuner"])] {
            XCTAssertEqual(Limites.para(tipoConexion: "RTMP", estado: e), .sinLimites)
            XCTAssertEqual(Limites.para(tipoConexion: "SRT", estado: e), .sinLimites)
        }
    }

    /// El motor corta solo la transmisión gratis a los 5 minutos y muestra el aviso.
    @MainActor
    func testMotorCortaLaVersionGratisALos5Minutos() {
        let motor = Motor()
        let reloj = RelojFalso()
        motor.reloj = reloj
        motor.empezarConteo(limites: .gratis)
        XCTAssertEqual(motor.restanteGratis, 300)
        reloj.avanzar(120)
        motor.tic()
        XCTAssertNil(motor.aviso)
        XCTAssertEqual(motor.restanteGratis, 180)
        reloj.avanzar(180)
        motor.tic()
        XCTAssertEqual(motor.aviso, Limites.avisoCorte)
    }

    @MainActor
    func testMotorConPlanNoCorta() {
        let motor = Motor()
        let reloj = RelojFalso()
        motor.reloj = reloj
        motor.empezarConteo(limites: .sinLimites)
        reloj.avanzar(3 * 3600)
        motor.tic()
        XCTAssertNil(motor.aviso)
        XCTAssertNil(motor.restanteGratis)
        XCTAssertEqual(motor.segundos, 3 * 3600)
    }
}
