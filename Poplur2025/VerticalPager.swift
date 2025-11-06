import SwiftUI

/// A vertically paging UIScrollView that hosts SwiftUI pages and reports the current index.
struct VerticalPager<Content: View>: UIViewControllerRepresentable {
    @Binding var currentIndex: Int
    let pageCount: Int
    let content: () -> Content

    init(currentIndex: Binding<Int>, pageCount: Int, @ViewBuilder content: @escaping () -> Content) {
        self._currentIndex = currentIndex
        self.pageCount = pageCount
        self.content = content
    }

    func makeUIViewController(context: Context) -> PagerViewController {
        let vc = PagerViewController()
        vc.onIndexChange = { index in
            if self.currentIndex != index {
                self.currentIndex = index
            }
        }
        return vc
    }

    func updateUIViewController(_ vc: PagerViewController, context: Context) {
        vc.update(pages: UIHostingController(rootView: content()), currentIndex: currentIndex)
    }
}

// MARK: - Internal UIViewController hosting a vertical paging UIScrollView

final class PagerViewController: UIViewController, UIScrollViewDelegate {
    var onIndexChange: ((Int) -> Void)?

    private let scrollView = UIScrollView()
    private var hostingVC: UIViewController?

    private var pageCount: Int = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.isPagingEnabled = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.delegate = self
        scrollView.backgroundColor = .black
        view.backgroundColor = .black
        view.addSubview(scrollView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds
        layoutPages()
    }

    func update(pages: UIViewController, currentIndex: Int) {
        // Replace hosting controller if needed
        if hostingVC !== pages {
            hostingVC?.willMove(toParent: nil)
            hostingVC?.view.removeFromSuperview()
            hostingVC?.removeFromParent()

            addChild(pages)
            scrollView.addSubview(pages.view)
            pages.didMove(toParent: self)
            hostingVC = pages
        }
        // Derive pageCount from hosted SwiftUI’s arranged content height once laid out
        // but we also require FeedView to size each page to screen height so we can compute count by content size / page height.
        layoutPages()
        let pageHeight = scrollView.bounds.height
        guard pageHeight > 0 else { return }
        let targetOffset = CGPoint(x: 0, y: CGFloat(currentIndex) * pageHeight)
        if scrollView.contentOffset != targetOffset {
            scrollView.setContentOffset(targetOffset, animated: false)
        }
    }

    private func layoutPages() {
        guard let hostedView = hostingVC?.view else { return }
        hostedView.frame = CGRect(origin: .zero, size: scrollView.bounds.size)
        hostedView.translatesAutoresizingMaskIntoConstraints = true

        // Ensure the hosted stack expands vertically via its intrinsic content.
        hostedView.setNeedsLayout()
        hostedView.layoutIfNeeded()

        // The hosted SwiftUI view is a vertical VStack of screen-sized pages; compute content size:
        let pageHeight = scrollView.bounds.height
        guard pageHeight > 0 else { return }

        // Ask SwiftUI view for its size; fallback to bounds height * estimated count.
        let contentHeight = hostedView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
        let computedCount = max(1, Int(round(contentHeight / pageHeight)))
        pageCount = computedCount

        scrollView.contentSize = CGSize(width: scrollView.bounds.width, height: CGFloat(pageCount) * pageHeight)
        hostedView.frame.size = scrollView.contentSize
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let pageHeight = max(scrollView.bounds.height, 1)
        let index = Int(round(scrollView.contentOffset.y / pageHeight))
        onIndexChange?(index)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            let pageHeight = max(scrollView.bounds.height, 1)
            let index = Int(round(scrollView.contentOffset.y / pageHeight))
            onIndexChange?(index)
        }
    }
}
