import HaishinKit
import SwiftUI

struct PantallaCamara: View {
    @EnvironmentObject var ajustes: Ajustes
    @EnvironmentObject var motor: Motor
    @State private var verAjustes = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MTHKViewRepresentable(previewSource: motor, videoGravity: .resizeAspectFill)
                .ignoresSafeArea()
            #if targetEnvironment(simulator)
            // El simulador no tiene camara: se muestra un fondo de ejemplo encima de la vista vacia.
            FondoSimulador().ignoresSafeArea()
            #endif
            VStack {
                HStack {
                    etiquetaEstado
                    Spacer()
                    Button { verAjustes = true } label: {
                        Image(systemName: "gearshape.fill").font(.title2).padding(10)
                    }
                    .accessibilityLabel("Ajustes")
                }
                .padding(.horizontal)
                if let c = ajustes.conexionActiva {
                    Text("\(c.nombre) · \(c.tipo)").font(.footnote).padding(6)
                        .background(.black.opacity(0.5)).cornerRadius(6)
                }
                Spacer()
                HStack(spacing: 28) {
                    botonRedondo(motor.silencio ? "mic.slash.fill" : "mic.fill", "Micrófono") { motor.alternarSilencio() }
                    Button {
                        if motor.enVivo || motor.conectando { motor.detener() } else { motor.transmitir(ajustes) }
                    } label: {
                        Circle()
                            .fill(motor.enVivo ? Color.red : Color.white)
                            .frame(width: 78, height: 78)
                            .overlay(Text(motor.enVivo ? "PARAR" : (motor.conectando ? "..." : "EN VIVO"))
                                .font(.caption.bold()).foregroundColor(motor.enVivo ? .white : .black))
                    }
                    .accessibilityLabel(motor.enVivo ? "Parar transmisión" : "Empezar transmisión")
                    botonRedondo("arrow.triangle.2.circlepath.camera.fill", "Cambiar cámara") { motor.cambiarCamara(ajustes) }
                }
                .padding(.bottom, 8)
                botonRedondo(motor.linterna ? "flashlight.on.fill" : "flashlight.off.fill", "Linterna") { motor.alternarLinterna() }
                    .padding(.bottom, 20)
            }
            .foregroundColor(.white)
        }
        .task {
            await motor.prenderCamara(ajustes)
            Prueba.anotar("CARGO TuBroadcast nativa - pantalla de camara abierta (camara: \(motor.camaraLista ? "si" : "no hay en el simulador"))")
        }
        .sheet(isPresented: $verAjustes) { PantallaAjustes().environmentObject(ajustes) }
        .onAppear {
            // Solo para las capturas de la App Store (argumento de arranque -abrirAjustes YES)
            if UserDefaults.standard.bool(forKey: "abrirAjustes") { verAjustes = true }
        }
        .alert(motor.aviso ?? "", isPresented: Binding(get: { motor.aviso != nil }, set: { if !$0 { motor.aviso = nil } })) {
            Button("Aceptar", role: .cancel) {}
        }
    }

    private var etiquetaEstado: some View {
        HStack(spacing: 6) {
            Circle().fill(motor.enVivo ? Color.red : (motor.conectando ? Color.orange : Color.gray)).frame(width: 10, height: 10)
            Text(motor.enVivo ? "EN VIVO \(motor.tiempoTexto)" : (motor.conectando ? "Conectando..." : "Listo"))
                .font(.subheadline.bold())
        }
        .padding(8).background(.black.opacity(0.5)).cornerRadius(8)
    }

    private func botonRedondo(_ icono: String, _ nombre: String, _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Image(systemName: icono).font(.title2).frame(width: 52, height: 52)
                .background(.black.opacity(0.5)).clipShape(Circle())
        }
        .accessibilityLabel(nombre)
    }
}

struct PantallaAjustes: View {
    @EnvironmentObject var ajustes: Ajustes
    @Environment(\.dismiss) private var cerrar
    @State private var editando: Conexion?

    var body: some View {
        NavigationStack {
            Form {
                Section("Conexiones") {
                    ForEach(ajustes.conexiones) { c in
                        HStack {
                            Image(systemName: ajustes.conexionActiva?.id == c.id ? "largecircle.fill.circle" : "circle")
                                .onTapGesture { ajustes.activa = c.id }
                            VStack(alignment: .leading) {
                                Text(c.nombre).bold()
                                Text("\(c.tipo) · \(c.url)").font(.caption).foregroundColor(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button("Editar") { editando = c }.buttonStyle(.borderless)
                        }
                    }
                    .onDelete { ajustes.conexiones.remove(atOffsets: $0) }
                    Button("Agregar conexión") {
                        editando = Conexion(nombre: "Conexión \(ajustes.conexiones.count + 1)", url: "srt://")
                    }
                }
                Section("Video") {
                    Picker("Resolución", selection: $ajustes.resolucion) {
                        ForEach(Resolucion.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Cuadros por segundo", selection: $ajustes.fps) {
                        ForEach([24, 25, 30, 50, 60], id: \.self) { Text("\($0)").tag($0) }
                    }
                    VStack(alignment: .leading) {
                        Text("Calidad (bitrate): \(Int(ajustes.bitrateKbps)) kbps")
                        Slider(value: $ajustes.bitrateKbps, in: 500...12000, step: 250)
                    }
                }
                Section("Ayuda") {
                    Text("El video va directo de este celular a su destino (YouTube, Facebook, vMix, OBS...). No pasa por servidores de Tukán.")
                        .font(.footnote)
                    Text("También puede cargar la configuración con un enlace tubroadcast://set/v1?... o larix://set/v1?...")
                        .font(.footnote)
                }
            }
            .navigationTitle("Ajustes")
            .toolbar { Button("Listo") { cerrar() } }
            .sheet(item: $editando) { c in
                EditorConexion(conexion: c) { nueva in
                    if let i = ajustes.conexiones.firstIndex(where: { $0.id == nueva.id }) {
                        ajustes.conexiones[i] = nueva
                    } else {
                        ajustes.conexiones.append(nueva)
                        if ajustes.activa == nil { ajustes.activa = nueva.id }
                    }
                }
            }
        }
    }
}

struct EditorConexion: View {
    @State var conexion: Conexion
    var guardar: (Conexion) -> Void
    @Environment(\.dismiss) private var cerrar

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre", text: $conexion.nombre)
                TextField("Dirección (rtmp://, rtmps:// o srt://)", text: $conexion.url)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                if conexion.tipo.hasPrefix("RTMP") {
                    SecureField("Clave de transmisión (stream key)", text: $conexion.clave)
                }
                if conexion.tipo == "SRT" {
                    Text("Ejemplo SRT: srt://servidor:9000?streamid=camara1&latency=200000&passphrase=clave123")
                        .font(.caption).foregroundColor(.secondary)
                }
                if let p = conexion.problema {
                    Text(p).foregroundColor(.orange).font(.footnote)
                }
            }
            .navigationTitle("Conexión")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guardar(conexion); cerrar() }.disabled(conexion.problema != nil)
                }
            }
        }
    }
}

/// Deja una nota para la prueba automatica del simulador (Documents/prueba_carga.txt).
enum Prueba {
    static func anotar(_ texto: String) {
        guard let carpeta = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let archivo = carpeta.appendingPathComponent("prueba_carga.txt")
        try? (texto + "\n").write(to: archivo, atomically: true, encoding: .utf8)
    }
}


#if targetEnvironment(simulator)
/// Fondo de ejemplo para el simulador (luces de escenario), porque no hay camara.
struct FondoSimulador: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.16),
                                    Color(red: 0.22, green: 0.10, blue: 0.35),
                                    Color(red: 0.85, green: 0.38, blue: 0.12)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.white.opacity(0.35), .clear], center: .init(x: 0.3, y: 0.35),
                           startRadius: 5, endRadius: 260)
            RadialGradient(colors: [Color.yellow.opacity(0.25), .clear], center: .init(x: 0.75, y: 0.25),
                           startRadius: 5, endRadius: 220)
        }
    }
}
#endif
