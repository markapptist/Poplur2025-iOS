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
        vc.update(pages: UIHostingController(rootView: content()), currentIndex: currentIndex, pageCount: pageCount)
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
        scrollView.clipsToBounds = true

        // Make sure we use the full bounds behind safe areas to match SwiftUI’s .ignoresSafeArea
        view.backgroundColor = .black
        view.addSubview(scrollView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds
        layoutPagesIfPossible()
    }

    func update(pages: UIViewController, currentIndex: Int, pageCount: Int) {
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

        self.pageCount = pageCount
        layoutPagesIfPossible()

        let pageHeight = scrollView.bounds.height
        guard pageHeight > 0 else { return }
        let targetOffset = CGPoint(x: 0, y: CGFloat(currentIndex) * pageHeight)
        if scrollView.contentOffset != targetOffset {
            scrollView.setContentOffset(targetOffset, animated: false)
        }
    }

    private func layoutPagesIfPossible() {
        guard let hostedView = hostingVC?.view else { return }
        let pageHeight = scrollView.bounds.height
        let pageWidth = scrollView.bounds.width
        guard pageHeight > 0, pageWidth > 0, pageCount > 0 else { return }

        // Content size is exactly pageCount * pageHeight
        let contentSize = CGSize(width: pageWidth, height: CGFloat(pageCount) * pageHeight)
        scrollView.contentSize = contentSize

        hostedView.frame = CGRect(origin: .zero, size: contentSize)
        hostedView.translatesAutoresizingMaskIntoConstraints = true
        hostedView.clipsToBounds = true
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
