// Licencia firmada (ECDSA P-256): válida, inválida, de otra llave, vencida, de otro celular y sin conexión más de 72 h.
import CryptoKit
import XCTest
@testable import TuBroadcast

final class PruebasLicencia: XCTestCase {
    let verificador = VerificadorLicencia(llavePublicaBase64: LlavePrueba.publicaBase64)
    let ahora = Date(timeIntervalSince1970: 1_795_000_000)
    var seg: Int64 { Int64(ahora.timeIntervalSince1970) }

    func testTextoFirmadoIgualAlPanelYAndroid() {
        let l = Licencia(dispositivo: "cel-1", cliente: "Productora Tukán", plan: "basico", modulos: ["rtmp", "grove", "abr"],
                         emitida: 100, vence: 200)
        XCTAssertEqual(l.textoFirmado, "cel-1|Productora Tukán|basico|abr,grove,rtmp|100|200|259200|0")
    }

    func testLicenciaValida() {
        let l = LlavePrueba.licencia(dispositivo: "cel-1", ahora: ahora)
        XCTAssertEqual(verificador.verificar(l, dispositivo: "cel-1", ahora: seg, ultimoContacto: seg), .valida(l))
    }

    func testLicenciaInvalidaSiLaCambian() {
        var l = LlavePrueba.licencia(dispositivo: "cel-1", plan: "basico", modulos: ["rtmp"], ahora: ahora)
        l.modulos.append("srt")   // alguien intenta darse SRT sin pagar
        guard case .gratis(let motivo) = verificador.verificar(l, dispositivo: "cel-1", ahora: seg, ultimoContacto: seg) else {
            return XCTFail("Una licencia alterada no debe valer")
        }
        XCTAssertTrue(motivo.contains("firma incorrecta"))
    }

    func testLicenciaFirmadaConOtraLlaveNoVale() {
        let l = LlavePrueba.licencia(dispositivo: "cel-1", ahora: ahora, con: P256.Signing.PrivateKey())
        XCTAssertFalse(verificador.verificar(l, dispositivo: "cel-1", ahora: seg, ultimoContacto: seg).esValida)
    }

    func testLicenciaSinFirmaNoVale() {
        var l = LlavePrueba.licencia(dispositivo: "cel-1", ahora: ahora)
        l.firma = ""
        XCTAssertFalse(verificador.verificar(l, dispositivo: "cel-1", ahora: seg, ultimoContacto: seg).esValida)
    }

    func testLicenciaVencida() {
        let l = LlavePrueba.licencia(dispositivo: "cel-1", ahora: ahora, horas: 24)
        let despues = seg + 24 * 3600 + 1
        guard case .gratis(let motivo) = verificador.verificar(l, dispositivo: "cel-1", ahora: despues, ultimoContacto: despues) else {
            return XCTFail("Una licencia vencida no debe valer")
        }
        XCTAssertTrue(motivo.contains("venció"))
    }

    func testPaseVencidoDiceQueTermino() {
        let l = LlavePrueba.licencia(dispositivo: "cel-1", plan: "dia", ahora: ahora, horas: 24)
        let despues = seg + 25 * 3600
        XCTAssertEqual(verificador.verificar(l, dispositivo: "cel-1", ahora: despues, ultimoContacto: despues),
                       .gratis("El pase de 24 horas terminó."))
    }

    func testLicenciaDeOtroCelular() {
        let l = LlavePrueba.licencia(dispositivo: "cel-1", ahora: ahora)
        XCTAssertEqual(verificador.verificar(l, dispositivo: "cel-2", ahora: seg, ultimoContacto: seg),
                       .gratis("La licencia es de otro celular."))
    }

    func testSinInternetValeHasta72Horas() {
        let l = LlavePrueba.licencia(dispositivo: "cel-1", ahora: ahora)
        XCTAssertTrue(verificador.verificar(l, dispositivo: "cel-1", ahora: seg + 72 * 3600, ultimoContacto: seg).esValida)
        XCTAssertEqual(verificador.verificar(l, dispositivo: "cel-1", ahora: seg + 72 * 3600 + 1, ultimoContacto: seg),
                       .gratis("Conéctate a internet para confirmar tu licencia."))
    }

    func testSinLicenciaEsGratis() {
        XCTAssertFalse(verificador.verificar(nil, dispositivo: "cel-1", ahora: seg, ultimoContacto: 0).esValida)
    }

    /// Firma hecha con openssl (lo mismo que hace el panel en PHP con openssl_sign): CryptoKit la debe aceptar.
    func testFirmaDeOpenSSLComoElPanel() {
        let publica = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEVr2CG0Sd6ykiaHWRqUIUShgchIoMt1PIPGl/8zGDtXdFTN+Bs3ukWgE9o9oSUpHOwG31B4jk4iQ2LvfJm8UsOg=="
        let l = Licencia(dispositivo: "celular-1234", cliente: "Productora Tukán", plan: "completo",
                         modulos: ["srt", "rtmp", "grove", "camara_pro", "abr"], emitida: 1_795_000_000, vence: 1_797_600_000,
                         firma: "MEQCIFiT4XXsq4uTSyyw0dW4ctMKpYJCHzOgyLwG/Sf3Ay4CAiAQotjUgvBdxS1bwjaZyCK4fdBX4EgZR+cnG52jPz3pbw==")
        let v = VerificadorLicencia(llavePublicaBase64: publica)
        XCTAssertTrue(v.firmaCorrecta(l))
        var mala = l
        mala.cliente = "Otro"
        XCTAssertFalse(v.firmaCorrecta(mala))
    }

    func testLaLlaveDelPanelSeLee() {
        // La llave real del panel (la misma de Android) debe ser una llave P-256 válida.
        XCTAssertNoThrow(try P256.Signing.PublicKey(derRepresentation: Data(base64Encoded: LlavePanel.publica)!))
    }

    func testLicenciaDelPanelEnJSON() throws {
        let json = #"{"dispositivo":"cel-1","cliente":"Cliente","plan":"basico","modulos":["rtmp","abr","grove"],"emitida":1,"vence":2,"maxSinConexionSeg":259200,"demo":false,"firma":"abc"}"#
        let l = try JSONDecoder().decode(Licencia.self, from: Data(json.utf8))
        XCTAssertEqual(l.plan, "basico")
        XCTAssertTrue(l.tiene("rtmp"))
        XCTAssertFalse(l.tiene("srt"))
    }
}
