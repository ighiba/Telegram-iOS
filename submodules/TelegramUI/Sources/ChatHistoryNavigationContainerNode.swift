import Foundation
import UIKit
import Display
import AsyncDisplayKit

public final class ChatHistoryNavigationContainerNode: SparseNode {
    override public init() {
        super.init()
        self.view.isUserInteractionEnabled = false
    }
}
