// Cascaron de iPhone para los programas Tukan.
// Abre la pagina web del programa a pantalla completa (lo que cambia en la web
// se ve en la app sin subir nada a Apple). Los datos de cada app vienen de
// Config.swift, que arma herramientas/generar.py desde apps/<app>/app.json.

import SwiftUI
import WebKit

@main
struct TukanApp: App {
    var body: some Scene {
        WindowGroup {
            PantallaPrincipal()
        }
    }
}

struct PantallaPrincipal: View {
    @StateObject private var estado = EstadoWeb()

    var body: some View {
        ZStack {
            Color(hex: Config.colorFondo).ignoresSafeArea()
            VistaWeb(estado: estado)
                .ignoresSafeArea(.container, edges: .bottom)
            if estado.sinInternet {
                SinInternet { estado.recargar() }
            } else if estado.cargando && !estado.yaCargoUnaVez {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.4)
            }
        }
    }
}

struct SinInternet: View {
    let reintentar: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash").font(.system(size: 48))
            Text("Sin conexión a internet").font(.title3.bold())
            Text("Revisa tu conexión y vuelve a intentar.")
                .multilineTextAlignment(.center)
            Button("Reintentar", action: reintentar)
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundColor(Color(hex: Config.colorFondo))
        }
        .foregroundColor(.white)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: Config.colorFondo).ignoresSafeArea())
    }
}

final class EstadoWeb: ObservableObject {
    @Published var cargando = true
    @Published var sinInternet = false
    @Published var yaCargoUnaVez = false
    weak var webView: WKWebView?

    func recargar() {
        sinInternet = false
        if let web = webView {
            if web.url == nil, let url = URL(string: Inicio.url) {
                web.load(URLRequest(url: url))
            } else {
                web.reload()
            }
        }
    }
}

struct VistaWeb: UIViewRepresentable {
    @ObservedObject var estado: EstadoWeb

    func makeCoordinator() -> Coordinador { Coordinador(estado: estado) }

    func makeUIView(context: Context) -> WKWebView {
        let ajustes = WKWebViewConfiguration()
        ajustes.allowsInlineMediaPlayback = true
        ajustes.websiteDataStore = .default()
        // Marca para que el servidor sepa que es la app de iPhone
        // (por ejemplo, para no mostrar botones de pago dentro de la app).
        ajustes.applicationNameForUserAgent = "TukanIOS/\(Config.version)"
        // Regla de Apple: dentro de la app de iPhone no se ven precios ni botones de pago de los planes.
        // Respaldo por si el servidor todavia no los esconde (ver Pagos mas abajo).
        ajustes.userContentController.addUserScript(
            WKUserScript(source: Pagos.scriptOcultar, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        let web = WKWebView(frame: .zero, configuration: ajustes)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = UIColor(Color(hex: Config.colorFondo))
        web.scrollView.backgroundColor = web.backgroundColor

        let refrescar = UIRefreshControl()
        refrescar.tintColor = .white
        refrescar.addTarget(context.coordinator, action: #selector(Coordinador.refrescar(_:)), for: .valueChanged)
        web.scrollView.refreshControl = refrescar

        estado.webView = web
        if let url = URL(string: Inicio.url) {
            web.load(URLRequest(url: url))
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinador: NSObject, WKNavigationDelegate, WKUIDelegate {
        let estado: EstadoWeb
        let dominioPropio: String?

        init(estado: EstadoWeb) {
            self.estado = estado
            self.dominioPropio = URL(string: Config.url)?.host
        }

        @objc func refrescar(_ control: UIRefreshControl) {
            estado.recargar()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { control.endRefreshing() }
        }

        // Los enlaces a otros sitios (WhatsApp, Telegram, mapas, pagos externos)
        // se abren fuera de la app.
        func webView(_ webView: WKWebView,
                     decidePolicyFor accion: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = accion.request.url else { return decisionHandler(.allow) }
            // Paginas de pago de los planes (Plux, Tukan Pagos, Google Play...): no se abren desde la app de iPhone.
            if Pagos.esDePago(url) {
                Prueba.anotar("BLOQUEADO pago: \(url.host ?? "")")
                return decisionHandler(.cancel)
            }
            let esquema = url.scheme?.lowercased() ?? ""
            if esquema == "tel" || esquema == "mailto" || esquema == "whatsapp" || esquema == "sms" {
                UIApplication.shared.open(url)
                return decisionHandler(.cancel)
            }
            if accion.targetFrame?.isMainFrame ?? false,
               esquema.hasPrefix("http"),
               let host = url.host, let propio = dominioPropio,
               !(host == propio || host.hasSuffix("." + propio)),
               accion.navigationType == .linkActivated {
                UIApplication.shared.open(url)
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }

        // target="_blank": dentro de la app si es del mismo sitio, fuera si no.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for accion: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = accion.request.url, !Pagos.esDePago(url) {
                if let host = url.host, let propio = dominioPropio,
                   host == propio || host.hasSuffix("." + propio) {
                    webView.load(URLRequest(url: url))
                } else {
                    UIApplication.shared.open(url)
                }
            }
            return nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            estado.cargando = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            estado.cargando = false
            estado.sinInternet = false
            estado.yaCargoUnaVez = true
            Prueba.anotar("CARGO \(webView.url?.absoluteString ?? "") | \(webView.title ?? "")")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fallo(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fallo(error)
        }

        private func fallo(_ error: Error) {
            estado.cargando = false
            let codigo = (error as NSError).code
            if codigo == NSURLErrorCancelled { return }
            Prueba.anotar("ERROR \(codigo) \(error.localizedDescription)")
            if [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
                NSURLErrorTimedOut, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost]
                .contains(codigo) {
                estado.sinInternet = true
            }
        }

        // Avisos de JavaScript (alert / confirm) de la pagina.
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage mensaje: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let aviso = UIAlertController(title: nil, message: mensaje, preferredStyle: .alert)
            aviso.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            Self.presentar(aviso, otherwise: completionHandler)
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage mensaje: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let aviso = UIAlertController(title: nil, message: mensaje, preferredStyle: .alert)
            aviso.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(false) })
            aviso.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in completionHandler(true) })
            Self.presentar(aviso) { completionHandler(false) }
        }

        private static func presentar(_ aviso: UIAlertController, otherwise: @escaping () -> Void) {
            let escena = UIApplication.shared.connectedScenes.first as? UIWindowScene
            guard let raiz = escena?.windows.first?.rootViewController else { return otherwise() }
            var arriba = raiz
            while let siguiente = arriba.presentedViewController { arriba = siguiente }
            arriba.present(aviso, animated: true)
        }
    }
}

// Deja una nota en la carpeta de la app para que la prueba automatica
// del simulador sepa si la pagina abrio bien.
enum Prueba {
    static func anotar(_ texto: String) {
        guard let carpeta = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let archivo = carpeta.appendingPathComponent("prueba_carga.txt")
        let linea = texto + "\n"
        if let manejador = try? FileHandle(forWritingTo: archivo) {
            manejador.seekToEndOfFile()
            manejador.write(linea.data(using: .utf8)!)
            try? manejador.close()
        } else {
            try? linea.write(to: archivo, atomically: true, encoding: .utf8)
        }
    }
}

extension Color {
    init(hex: String) {
        var limpio = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if limpio.hasPrefix("#") { limpio.removeFirst() }
        var valor: UInt64 = 0
        Scanner(string: limpio).scanHexInt64(&valor)
        self.init(red: Double((valor >> 16) & 0xFF) / 255,
                  green: Double((valor >> 8) & 0xFF) / 255,
                  blue: Double(valor & 0xFF) / 255)
    }
}


/// Regla de Apple (App Store 3.1.1): los planes de Tukan se pagan por la web, asi que la app de iPhone
/// no muestra precios de los planes, ni botones o enlaces para pagarlos. El servidor de cada programa
/// los esconde cuando el navegador dice «TukanIOS»; esto es el respaldo dentro de la app.
enum Pagos {
    /// Sitios de pago que nunca se abren desde la app.
    static let sitios = ["pagos.tukanec.com", "pagoplux.com", "payphonetodoesposible.com", "paypal.com",
                         "checkout.stripe.com", "play.google.com", "pay.google.com"]

    static func esDePago(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        if sitios.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return true }
        let resto = ((url.query ?? "") + "&" + url.path).lowercased()
        return resto.contains("r=play_compra") || resto.contains("r=pagar_plan") || resto.contains("r=comprar_plan")
    }

    /// CSS que esconde las partes de pago comunes de los programas Tukan y marca la pagina como app de iPhone
    /// (clase «tukan-ios» en <html>, para que el servidor pueda usar .tukan-ios en su CSS).
    static let scriptOcultar = """
    (function () {
      var css = '.tukan-pago,#pago-tarjeta,.tukan-sugerencia,#pago-play,.boton-play,.modulo-precio,' +
                '.tk-precio-plan,.precio-plan,.solo-web,[data-tukan-pago],[data-solo-web],' +
                'a[href*="pagos.tukanec.com"],a[href*="pagoplux"],a[href*="payphone"],a[href*="play_compra"]' +
                '{display:none!important}';
      var poner = function () {
        document.documentElement.classList.add('tukan-ios');
        if (document.getElementById('tukan-ios-css')) return;
        var s = document.createElement('style'); s.id = 'tukan-ios-css'; s.textContent = css;
        (document.head || document.documentElement).appendChild(s);
      };
      poner();
      document.addEventListener('DOMContentLoaded', poner);
    })();
    """
}


/// Direccion con la que abre la app. Normalmente es Config.url; solo para sacar
/// capturas de la App Store se puede abrir otra pagina del MISMO sitio con
/// `simctl launch ... -capturaURL https://...` (argumento de arranque).
enum Inicio {
    static var url: String {
        if let otra = UserDefaults.standard.string(forKey: "capturaURL"),
           let host = URL(string: otra)?.host,
           host == URL(string: Config.url)?.host {
            return otra
        }
        return Config.url
    }
}
