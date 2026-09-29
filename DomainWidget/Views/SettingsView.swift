import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    @State private var newTLD = ""
    @State private var apiKeyInput = ""
    @State private var hasAPIKey = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                TLDPicker()
                HStack {
                    TextField("Añadir extensión (ej. shop)", text: $newTLD)
                        .domainInputStyle()
                        .onSubmit(addTLD)
                    Button("Añadir", action: addTLD)
                        .disabled(newTLD.isEmpty)
                }
                Picker("Extensión por defecto en masivo", selection: $settings.bulkDefaultTLD) {
                    ForEach(settings.allTLDs, id: \.self) { Text(".\($0)").tag($0) }
                }
            } header: {
                Text("Extensiones para buscar")
            }

            Section {
                Toggle("Avisos de vigilancia", isOn: $settings.watchNotifications)
                Stepper("Avisar \(settings.expiryWarningDays) días antes de caducar", value: $settings.expiryWarningDays, in: 1...120)
            } header: {
                Text("Vigilancia")
            }

            Section {
                TextField("Endpoint", text: $settings.aiEndpoint)
                    .domainInputStyle()
                TextField("Modelo", text: $settings.aiModel)
                    .domainInputStyle()
                SecureField(hasAPIKey ? "Clave guardada (escribe otra para cambiarla)" : "Clave de API", text: $apiKeyInput)
                HStack {
                    Button("Guardar clave") {
                        settings.aiAPIKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        apiKeyInput = ""
                        hasAPIKey = settings.aiAPIKey != nil
                    }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    if hasAPIKey {
                        Button("Borrar clave", role: .destructive) {
                            settings.aiAPIKey = nil
                            hasAPIKey = false
                        }
                    }
                }
            } header: {
                Text("Sugerencias con IA (opcional)")
            } footer: {
                Text("Compatible con OpenAI y APIs con el mismo formato (chat/completions). La clave se guarda en el Llavero de este dispositivo; nunca en el código, en el repositorio ni en iCloud.")
            }

            Section {
                ForEach(Registrar.allCases) { registrar in
                    TextField(registrar.name, text: affiliateBinding(registrar), prompt: Text("ej. aff=12345"))
                        .domainInputStyle()
                }
            } header: {
                Text("Parámetros de afiliado")
            } footer: {
                Text("Se añaden a los enlaces «Registrar en…». Déjalo vacío si no tienes programa de afiliados.")
            }

            Section {
                Text("Favoritos, historial y vigilancia se sincronizan entre Mac e iPhone con iCloud cuando la app tiene activada la capacidad iCloud (almacén clave-valor). Eso requiere una cuenta de desarrollador de pago; con un Apple ID gratuito se guardan solo en este dispositivo.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Sincronización")
            }

            Section {
                LabeledContent("Versión", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                LabeledContent("Registro", value: "RDAP (bootstrap de IANA)")
                LabeledContent("DNS", value: "DNS sobre HTTPS (Cloudflare, Google)")
                LabeledContent("Geolocalización", value: "ipwho.is")
            } header: {
                Text("Acerca de")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Ajustes")
        .onAppear { hasAPIKey = settings.aiAPIKey != nil }
    }

    private func addTLD() {
        settings.addCustomTLD(newTLD)
        newTLD = ""
    }

    private func affiliateBinding(_ registrar: Registrar) -> Binding<String> {
        Binding(
            get: { settings.affiliateParameters[registrar.rawValue] ?? "" },
            set: { settings.affiliateParameters[registrar.rawValue] = $0.isEmpty ? nil : $0 }
        )
    }
}
