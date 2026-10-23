import CoreMediaIO
import Foundation

let sorgente = SorgenteProvider(codaClient: nil)
CMIOExtensionProvider.startService(provider: sorgente.provider)
CFRunLoopRun()
