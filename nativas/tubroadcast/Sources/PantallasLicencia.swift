// Pantallas de licencia: Planes (compra con Apple), Activar con código y la sección Licencia de Ajustes.
// Regla de Apple 3.1.1 / 3.1.3(b): aquí NO hay enlaces ni textos que manden a comprar fuera de la app
// (ni web, ni precios externos, ni otros medios de pago). Solo la compra de Apple y el campo para el código.
import StoreKit
import SwiftUI

enum EnlacesLegales {
    static let terminos = URL(string: "https://tukansoftware.com/terminos.html")!
    static let privacidad = URL(string: "https://tuner.tukanec.com/?r=privacidad")!
}

struct PantallaPlanes: View {
    @EnvironmentObject var tienda: Tienda
    @EnvironmentObject var gestor: GestorLicencia
    @State private var celulares = 1
    @State private var aviso: String?
    @State private var comprado: RespuestaActivacion?

    var body: some View {
        List {
            Section {
                Text("Sin plan, TuBroadcast transmite gratis hasta 5 minutos, en 720p y con la marca de agua «TuBroadcast».")
                    .font(.footnote)
                Picker("Celulares", selection: $celulares) {
                    ForEach(InfoProducto.celularesPosibles, id: \.self) { n in
                        Text(n == 1 ? "1 celular" : "\(n) celulares").tag(n)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("¿Para cuántos celulares?")
            }

            Section {
                if tienda.cargando && tienda.productos.isEmpty {
                    HStack { ProgressView(); Text("Cargando planes…") }
                } else if tienda.productos(celulares: celulares).isEmpty {
                    Text("No hay planes disponibles en este momento.").foregroundColor(.secondary)
                    Button("Intentar otra vez") { Task { await tienda.cargarProductos() } }
                }
                ForEach(tienda.productos(celulares: celulares), id: \.id) { p in
                    if let info = InfoProducto.de(p.id) { filaProducto(p, info) }
                }
            } header: {
                Text("Planes")
            }

            Section {
                Button("Restaurar compras") {
                    Task { aviso = await tienda.restaurar() }
                }
                NavigationLink("Activar con código") { PantallaActivarCodigo() }
                Button("Gestionar suscripción") { Task { await tienda.gestionarSuscripcion() } }
            }

            Section {
                Text("Los planes mensuales y anuales son suscripciones que se renuevan solas al final de cada período, al mismo precio, hasta que las canceles. El cobro se hace a tu cuenta de Apple al confirmar la compra. Puedes cancelar cuando quieras en Ajustes del iPhone > tu nombre > Suscripciones, al menos 24 horas antes de que termine el período. El Pase de 24 horas es un solo pago y no se renueva.")
                    .font(.caption).foregroundColor(.secondary)
                Link("Términos de uso", destination: EnlacesLegales.terminos)
                Link("Política de privacidad", destination: EnlacesLegales.privacidad)
            }
        }
        .navigationTitle("Planes")
        .disabled(tienda.trabajando)
        .overlay { if tienda.trabajando { ProgressView().controlSize(.large) } }
        .task { if tienda.productos.isEmpty { await tienda.cargarProductos() } }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) {
            Button("Aceptar", role: .cancel) {}
        }
        .sheet(item: Binding(get: { comprado.map { CompraHecha(respuesta: $0) } }, set: { if $0 == nil { comprado = nil } })) { c in
            PantallaCompraHecha(respuesta: c.respuesta)
        }
    }

    private func filaProducto(_ p: Product, _ info: InfoProducto) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.titulo + (info.periodo == .anio ? " anual" : info.periodo == .mes ? " mensual" : "")).font(.headline)
                    Text(info.textoCelulares).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(p.displayPrice).font(.headline)
                    Text(info.textoPeriodo).font(.caption).foregroundColor(.secondary)
                }
            }
            Text(info.descripcion).font(.footnote)
            Button {
                Task {
                    switch await tienda.comprar(p) {
                    case .listo(let r): comprado = r
                    case .cancelada: break
                    case .pendiente: aviso = "La compra está pendiente de aprobación. Cuando se apruebe, el plan se activa solo."
                    case .error(let m): aviso = m
                    }
                }
            } label: {
                Text(info.periodo == .pase ? "Comprar pase" : "Suscribirme")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("\(info.titulo), \(info.textoCelulares), \(p.displayPrice) \(info.textoPeriodo)")
        }
        .padding(.vertical, 4)
    }
}

private struct CompraHecha: Identifiable {
    let respuesta: RespuestaActivacion
    var id: String { respuesta.token + (respuesta.codigo ?? "") }
}

/// Después de comprar: confirma y muestra el código del paquete para los otros celulares.
struct PantallaCompraHecha: View {
    let respuesta: RespuestaActivacion
    @Environment(\.dismiss) private var cerrar

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(respuesta.mensaje.isEmpty ? "¡Listo! Tu plan está activo en este celular." : respuesta.mensaje,
                          systemImage: "checkmark.seal.fill")
                        .foregroundColor(.green)
                }
                if let codigo = respuesta.codigo, !codigo.isEmpty, (respuesta.celulares ?? 1) > 1 {
                    BloqueCodigo(codigo: codigo, celulares: respuesta.celulares ?? 1)
                }
            }
            .navigationTitle("Compra hecha")
            .toolbar { Button("Listo") { cerrar() } }
        }
    }
}

/// Código del paquete con botones para copiar y compartir.
struct BloqueCodigo: View {
    let codigo: String
    let celulares: Int
    @State private var copiado = false

    var body: some View {
        Section {
            Text(codigo).font(.system(.title2, design: .monospaced).bold()).textSelection(.enabled)
            Text("Comparte este código con los otros celulares del paquete (\(celulares) en total). En cada uno: Ajustes > Licencia > Activar con código.")
                .font(.footnote)
            HStack {
                Button(copiado ? "Copiado" : "Copiar") {
                    UIPasteboard.general.string = codigo
                    copiado = true
                }
                .buttonStyle(.bordered)
                Spacer()
                ShareLink(item: codigo, message: Text("Código de TuBroadcast para activar este celular: \(codigo)")) {
                    Label("Compartir", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
        } header: {
            Text("Código del paquete")
        }
    }
}

struct PantallaActivarCodigo: View {
    @EnvironmentObject var gestor: GestorLicencia
    @Environment(\.dismiss) private var cerrar
    @State private var codigo = ""
    @State private var trabajando = false
    @State private var resultado: String?
    @State private var activado = false

    var body: some View {
        Form {
            Section {
                TextField("TB-XXXX-XXXX", text: $codigo)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.title3, design: .monospaced))
                Button {
                    trabajando = true
                    Task {
                        let (ok, mensaje) = await gestor.activar(codigo: codigo)
                        activado = ok
                        resultado = mensaje
                        trabajando = false
                    }
                } label: {
                    HStack { Text("Activar"); if trabajando { Spacer(); ProgressView() } }
                }
                .disabled(trabajando || codigo.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Código de activación")
            } footer: {
                Text("Si te dieron un código TB-XXXX-XXXX (por ejemplo, para los otros celulares de un paquete), escríbelo aquí.")
            }
        }
        .navigationTitle("Activar con código")
        .alert(resultado ?? "", isPresented: Binding(get: { resultado != nil }, set: { if !$0 { resultado = nil } })) {
            Button("Aceptar", role: .cancel) { if activado { cerrar() } }
        }
    }
}

/// Sección «Licencia» de Ajustes.
struct SeccionLicencia: View {
    @EnvironmentObject var gestor: GestorLicencia
    @EnvironmentObject var tienda: Tienda
    @State private var confirmarLiberar = false
    @State private var aviso: String?
    @State private var trabajando = false

    var body: some View {
        Section {
            switch gestor.estado {
            case .valida(let l):
                VStack(alignment: .leading, spacing: 4) {
                    Label("Plan \(l.nombrePlan)", systemImage: "checkmark.seal.fill").foregroundColor(.green).font(.headline)
                    Text("Vigente hasta el \(Self.fecha(l.vence))").font(.footnote)
                    if !l.cliente.isEmpty { Text(l.cliente).font(.footnote).foregroundColor(.secondary) }
                }
            case .gratis(let motivo):
                VStack(alignment: .leading, spacing: 4) {
                    Label("Versión gratis", systemImage: "lock.open").font(.headline)
                    Text("Hasta 5 minutos por transmisión, 720p y marca de agua «TuBroadcast».").font(.footnote)
                    if !motivo.isEmpty && gestor.tieneToken { Text(motivo).font(.footnote).foregroundColor(.orange) }
                }
            }
            if tienda.hayPlanes || gestor.tieneToken {
                NavigationLink("Ver planes") { PantallaPlanes() }
                NavigationLink("Activar con código") { PantallaActivarCodigo() }
                Button("Restaurar compras") { Task { aviso = await tienda.restaurar() } }
                Button("Gestionar suscripción") { Task { await tienda.gestionarSuscripcion() } }
            }
            if gestor.tieneToken {
                Button("Liberar este celular", role: .destructive) { confirmarLiberar = true }
                    .disabled(trabajando)
            }
        } header: {
            Text("Licencia")
        } footer: {
            if tienda.hayPlanes || gestor.tieneToken {
                Text("«Liberar este celular» deja libre su lugar en el plan para activar otro celular. No cancela tu suscripción de Apple: para cancelarla usa «Gestionar suscripción».")
            }
        }
        if let p = gestor.paquete, p.celulares > 1 {
            BloqueCodigo(codigo: p.codigo, celulares: p.celulares)
        }
        Section {
            Text("Id de este celular: \(gestor.dispositivo)").font(.caption2).foregroundColor(.secondary).textSelection(.enabled)
        }
        .confirmationDialog("¿Liberar este celular?", isPresented: $confirmarLiberar, titleVisibility: .visible) {
            Button("Liberar", role: .destructive) {
                trabajando = true
                Task {
                    aviso = await gestor.liberar().1
                    trabajando = false
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Este celular vuelve a la versión gratis y su lugar queda libre para otro celular.")
        }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) {
            Button("Aceptar", role: .cancel) {}
        }
    }

    static func fecha(_ epoch: Int64) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_EC")
        f.dateFormat = "d 'de' MMMM 'de' yyyy, HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }
}
