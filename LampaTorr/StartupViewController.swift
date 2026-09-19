import UIKit

final class StartupViewController: UIViewController {
    private let spinner = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()
    private let retryButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.114, green: 0.122, blue: 0.125, alpha: 1)
        configureUI()
        startServices()
    }

    private func configureUI() {
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "Запуск встроенного TorrServer…"
        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.setTitle("Повторить", for: .normal)
        retryButton.isHidden = true
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        view.addSubview(spinner)
        view.addSubview(statusLabel)
        view.addSubview(retryButton)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 18),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            retryButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            retryButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    @objc private func retryTapped() {
        retryButton.isHidden = true
        spinner.startAnimating()
        startServices()
    }

    private func startServices() {
        statusLabel.text = "Запуск встроенного TorrServer…"

        TorrServerManager.shared.start { [weak self] torrResult in
            guard let self else { return }

            switch torrResult {
            case .failure(let error):
                self.show(error)
            case .success:
                self.statusLabel.text = "Запуск Lampa…"

                LampaHTTPServer.shared.start { [weak self] webResult in
                    guard let self else { return }

                    switch webResult {
                    case .failure(let error):
                        self.show(error)
                    case .success:
                        self.showLampa()
                    }
                }
            }
        }
    }

    private func show(_ error: Error) {
        spinner.stopAnimating()
        statusLabel.text = error.localizedDescription
        retryButton.isHidden = false
    }

    private func showLampa() {
        guard let window = view.window else { return }

        UIView.transition(with: window, duration: 0.25, options: .transitionCrossDissolve) {
            window.rootViewController = LampaViewController()
        }
    }
}
