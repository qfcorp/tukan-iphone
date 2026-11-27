// Pantallas de licencia: Planes (compra con Apple) y la sección Licencia de Ajustes.
// Regla de Apple 3.1.1 (revisión del 27 nov 2026): en iPhone los planes se desbloquean SOLO con In-App Purchase.
// Aquí NO hay campo para escribir códigos ni tokens, ni enlaces o textos que manden a comprar fuera de la app
// (ni web, ni precios externos, ni otros medios de pago). Solo la compra de Apple, Restaurar compras y Gestionar suscripción.
import StoreKit
import SwiftUI

enum EnlacesLegales {
    static let terminos = URL(string: "https://tukansoftware.com/terminos.html")!
    static let privacidad = URL(string: "https://tuner.tukanec.com/?r=privacidad")!
}

struct PantallaPlanes: View {
    @EnvironmentObject var tienda: Tienda
    @EnvironmentObject var gestor: GestorLicencia
    @State private var celulares: Int
    @State private var aviso: String?

    init(celularesIniciales: Int = 1) {
        _celulares = State(initialValue: celularesIniciales)
    }

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
            } footer: {
                if celulares > 1 {
                    Text("Para usar el plan en los otros iPhone, abre TuBroadcast en cada uno con la misma cuenta de Apple y toca «Restaurar compras».")
                }
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
                    case .listo(let r): aviso = r.mensaje
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
                Text("Los planes se compran dentro de la app con tu cuenta de Apple. «Liberar este celular» deja libre su lugar en el plan para usarlo en otro iPhone con la misma cuenta de Apple («Restaurar compras»). No cancela tu suscripción de Apple: para cancelarla usa «Gestionar suscripción».")
            }
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
