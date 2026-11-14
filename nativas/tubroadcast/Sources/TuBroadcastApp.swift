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
                        // Solo para las capturas de la App Store (argumento de arranque -enlaceDemo):
                        // carga conexiones de ejemplo sin mostrar aviso.
                        if let demo = UserDefaults.standard.string(forKey: "enlaceDemo"),
                           let url = URL(string: demo), ajustes.conexiones.isEmpty {
                            _ = ajustes.importarEnlace(url)
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
