// TuBroadcast para iPhone (familia Tukan) - transmite en vivo por RTMP/RTMPS y SRT desde el celular.
// El video va directo del celular al destino del cliente (YouTube, Facebook, vMix...). No pasa por servidores de Tukan.
import HaishinKit
import RTMPHaishinKit
import SRTHaishinKit
import SwiftUI

@main
struct TuBroadcastApp: App {
    @StateObject private var ajustes = Ajustes()
    @StateObject private var motor = Motor()
    @State private var iniciado = false

    var body: some Scene {
        WindowGroup {
            Group {
                if iniciado {
                    PantallaCamara()
                        .environmentObject(ajustes)
                        .environmentObject(motor)
                } else {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        Text("TuBroadcast").font(.largeTitle.bold()).foregroundColor(.white)
                    }
                    .task {
                        await StreamSessionBuilderFactory.shared.register(RTMPSessionFactory())
                        await StreamSessionBuilderFactory.shared.register(SRTSessionFactory())
                        // Solo para las capturas de la App Store (argumento de arranque -conexionesDemo YES):
                        // carga dos conexiones de ejemplo sin mostrar aviso.
                        if UserDefaults.standard.bool(forKey: "conexionesDemo"), ajustes.conexiones.isEmpty {
                            ajustes.conexiones = [
                                Conexion(nombre: "Estadio - vMix", url: "srt://192.168.1.50:9000"),
                                Conexion(nombre: "YouTube Live", url: "rtmp://a.rtmp.youtube.com/live2", clave: "abcd-efgh-ijkl")]
                            ajustes.activa = ajustes.conexiones.first?.id
                            ajustes.resolucion = .p1080
                            ajustes.bitrateKbps = 4500
                        }
                        iniciado = true
                    }
                }
            }
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                // tubroadcast://set/v1?... o larix://set/v1?... (configuracion por QR o enlace)
                let n = ajustes.importarEnlace(url)
                motor.aviso = n > 0 ? "Se cargaron \(n) conexiones" : "El enlace no trae conexiones"
            }
        }
    }
}
