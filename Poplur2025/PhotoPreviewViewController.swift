import UIKit

final class PhotoPreviewViewController: UIViewController {
    private let image: UIImage
    private let imageView = UIImageView()
    private let closeButton = UIButton(type: .system)
    private let postButton = UIButton(type: .system)
    
    var onPost: ((UIImage) -> Void)?

    init(image: UIImage) {
        self.image = image
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.image = image
        view.addSubview(imageView)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        // Post button
        postButton.translatesAutoresizingMaskIntoConstraints = false
        postButton.setTitle("Post", for: .normal)
        postButton.setTitleColor(.white, for: .normal)
        postButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 17)
        postButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.9)
        postButton.layer.cornerRadius = 8
        var config = UIButton.Configuration.filled()
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        postButton.configuration = config
        postButton.addTarget(self, action: #selector(postTapped), for: .touchUpInside)
        view.addSubview(postButton)

        NSLayoutConstraint.activate([
            postButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            postButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    @objc private func dismissSelf() {
        dismiss(animated: true, completion: nil)
    }
    
    @objc private func postTapped() {
        onPost?(image)
    }
}
