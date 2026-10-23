import SwiftUI

/// Impostazioni (bozza grafica, iPhone 2). Per ora si salvano soltanto: le userà il round 1.
struct SchermataImpostazioni: View {
    @AppStorage("risoluzione") private var risoluzione = "1080p"
    @AppStorage("fps") private var fps = 30
    @AppStorage("microfono") private var microfono = true
    @AppStorage("riduciSeCaldo") private var riduciSeCaldo = true

    var body: some View {
        Form {
            Section("Video") {
                Picker("Risoluzione", selection: $risoluzione) {
                    Text("720p").tag("720p")
                    Text("1080p").tag("1080p")
                    Text("4K").tag("4K")
                }
                Picker("Fotogrammi", selection: $fps) {
                    Text("24 fps").tag(24)
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
            }
            Section("Audio") {
                Toggle("Microfono dell'iPhone", isOn: $microfono)
            }
            Section("Durante l'uso") {
                Toggle("Riduci qualità se si scalda", isOn: $riduciSeCaldo)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Tema.fondo)
        .navigationTitle("Impostazioni")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
