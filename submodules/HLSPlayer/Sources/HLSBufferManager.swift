import Foundation

public enum HLSBufferState {
    case full
    case need(count: Int)
}

public class HLSBufferManager<Item> {
    var didAddItems: (() -> Void)?
    var didFilledBuffer: (() -> Void)?
    var didFreedBuffer: ((Int) -> Void)?
    var didEmptiedBuffer: (() -> Void)?
    
    var state: HLSBufferState {
        if buffer.count >= maxBufferSize {
            return .full
        } else {
            return .need(count: maxBufferSize - buffer.count)
        }
    }
    
    var firstItem: Item? {
        bufferLock.lock()
        let item: Item? = buffer.first
        bufferLock.unlock()
        return item
    }
    
    var isEmpty: Bool {
        bufferLock.lock()
        let isEmpty = buffer.isEmpty
        bufferLock.unlock()
        return isEmpty
    }
    
    var bufferSize: Int {
        bufferLock.lock()
        let count = buffer.count
        bufferLock.unlock()
        return count
    }
    
    private var buffer: [Item] = [] {
        didSet {
            if isLoggingEnabled { log() }
            if buffer.count >= maxBufferSize {
                didFilledBuffer?()
            } else if buffer.count < maxBufferSize && oldValue.count > buffer.count {
                didFreedBuffer?(maxBufferSize - buffer.count)
            } else if buffer.isEmpty {
                didEmptiedBuffer?()
            }
        }
    }
    
    let bufferLock = NSLock()
    
    var maxBufferSize: Int
    let label: String
    let isLoggingEnabled: Bool
    
    init(maxBufferSize: Int, label: String, isLoggingEnabled: Bool) {
        self.maxBufferSize = maxBufferSize
        self.label = label
        self.isLoggingEnabled = isLoggingEnabled
    }
    
    public func addItem(_ item: Item) {
        bufferLock.lock()
        buffer.append(item)
        bufferLock.unlock()
        didAddItems?()
    }
    
    public func addItems(_ items: [Item]) {
        bufferLock.lock()
        buffer.append(contentsOf: items)
        bufferLock.unlock()
        didAddItems?()
    }
    
    public func getNextItem() -> Item? {
        bufferLock.lock()
        var item: Item? = nil
        if !buffer.isEmpty {
            item = buffer.removeFirst()
        }
        bufferLock.unlock()
        return item
    }
    
    public func getNextItems(count: Int) -> [Item]? {
        guard count > 0 else { return nil }
        bufferLock.lock()
        var items: [Item]? = nil
        let itemsToGetCount = min(count, buffer.count)
        items = Array(buffer[0..<itemsToGetCount])
        buffer.removeFirst(itemsToGetCount)
        bufferLock.unlock()
        return items
    }
    
    func flush() {
        bufferLock.lock()
        buffer = []
        print("\(label) buffer flush")
        bufferLock.unlock()
    }
    
    private func log() {
        if buffer.count == 0 {
            print("WARNING: \(label) BUFFER IS EMPTY")
        } else {
            print("\(label) buffer: \(buffer.count)")
        }
    }
}

final class HLSBufferManagersContext {
    let videoFrameBufferManager: HLSBufferManager<HLSMediaFrame>
    let textureBufferManager: HLSBufferManager<HLSTexture>

    let audioFrameBufferManager: HLSBufferManager<HLSMediaFrame>
    let pcmBufferManager: HLSBufferManager<HLSAudioBuffer>
    
    init(
        videoFrameBufferManager: HLSBufferManager<HLSMediaFrame>,
        textureBufferManager: HLSBufferManager<HLSTexture>,
        audioFrameBufferManager: HLSBufferManager<HLSMediaFrame>,
        pcmBufferManager: HLSBufferManager<HLSAudioBuffer>
    ) {
        self.videoFrameBufferManager = videoFrameBufferManager
        self.textureBufferManager = textureBufferManager
        self.audioFrameBufferManager = audioFrameBufferManager
        self.pcmBufferManager = pcmBufferManager
    }
    
    func flushBuffers() {
        self.videoFrameBufferManager.flush()
        self.textureBufferManager.flush()
        self.audioFrameBufferManager.flush()
        self.pcmBufferManager.flush()
    }
    
    func isBuffersEmpty() -> Bool {
        return audioFrameBufferManager.isEmpty &&
               videoFrameBufferManager.isEmpty &&
               textureBufferManager.isEmpty &&
               pcmBufferManager.isEmpty
    }
}
