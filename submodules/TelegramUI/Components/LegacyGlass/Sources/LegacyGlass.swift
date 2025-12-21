import Foundation
import UIKit
import MetalKit

private final class BundleMarker: NSObject {
}

private var metalLibraryValue: MTLLibrary?
func metalLibrary(device: MTLDevice) -> MTLLibrary? {
    if let metalLibraryValue {
        return metalLibraryValue
    }
    // let library = device.makeDefaultLibrary()

    let mainBundle = Bundle(for: BundleMarker.self)
    guard let path = mainBundle.path(forResource: "LegacyGlassMetalResourcesBundle", ofType: "bundle") else {
        return nil
    }
    guard let bundle = Bundle(path: path) else {
        return nil
    }
    guard let library = try? device.makeDefaultLibrary(bundle: bundle) else {
        return nil
    }
    metalLibraryValue = library
    
    return library
}
