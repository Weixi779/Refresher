// Created by weixi on 2026/10/13.

@testable import Refresher
import Testing
import UIKit

@MainActor
struct ScrollToTopControllerTests {
    @Test("A previous UIKit end callback cannot cancel the new return")
    func previousMotionEndsBeforeNewTarget() {
        let scroll = EndingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        scroll.contentSize = CGSize(width: 320, height: 4000)
        scroll.contentOffset.y = 800
        let window = UIWindow(frame: scroll.bounds)
        let owner = UIViewController()
        owner.view.addSubview(scroll)
        window.rootViewController = owner
        window.isHidden = false
        defer { window.isHidden = true }
        let controller = ScrollToTopController(scrollView: scroll)
        scroll.oldMotionEnded = { controller.scrollViewDidEndScrollingAnimation() }
        controller.scroll(to: CGPoint(x: 0, y: -120), animated: true)
        #expect(scroll.oldMotionEnded == nil)
        #expect(controller.isScrolling)
        controller.cancel()
    }

    @Test(
        "Injected layout cooperation is balanced on every return exit",
        arguments: ["arrival", "earlyEnd", "cancel", "gesture"]
    )
    func layoutCompensation(exit: String) async {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        scroll.contentSize = CGSize(width: 320, height: 4000)
        let window = UIWindow(frame: scroll.bounds)
        let owner = UIViewController()
        owner.view.addSubview(scroll)
        window.rootViewController = owner
        window.isHidden = false
        defer { window.isHidden = true }
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentInset.top = 120
        scroll.contentOffset.y = 800
        var activity: [Bool] = []
        let controller = ScrollToTopController(scrollView: scroll, onActivityChanged: { activity.append($0) })
        controller.scroll(to: CGPoint(x: 0, y: -120), animated: true)
        #expect(activity == [true])
        var outcome: Bool?
        let waiter = Task { @MainActor in outcome = await controller.waitUntilFinished() }
        await Task.yield()
        switch exit {
        case "arrival":
            scroll.contentOffset.y = -120
            controller.scrollViewDidEndScrollingAnimation()
        case "earlyEnd": controller.scrollViewDidEndScrollingAnimation()
        case "gesture": controller.cancel(stopsAnimation: false)
        default: controller.cancel()
        }
        await waiter.value
        #expect(outcome == (exit == "arrival"))
        #expect(!controller.isScrolling)
        #expect(activity == [true, false])
        controller.cancel()
        #expect(activity == [true, false])
    }
}

@MainActor
private final class EndingScrollView: UIScrollView {
    var oldMotionEnded: (() -> Void)?
    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        let callback = oldMotionEnded
        oldMotionEnded = nil
        callback?()
        super.setContentOffset(contentOffset, animated: animated)
    }
}
