import AuthenticationServices
import SwiftUI

@MainActor
final class AppleAuthorizationPresenter: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    weak var window: UIWindow?
    private var presentationWindow: UIWindow?
    private var controller: ASAuthorizationController?
    private var completion: ((Result<ASAuthorization, Error>) -> Void)?

    func begin(onRequest: (ASAuthorizationAppleIDRequest) -> Void,
               onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        guard controller == nil else { return }
        guard let window, window.windowScene?.activationState == .foregroundActive else {
            onCompletion(.failure(AuthenticationError.unavailable))
            return
        }
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        onRequest(request)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        self.controller = controller
        presentationWindow = window
        completion = onCompletion
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // begin() retains the actual button's window throughout authorization.
        presentationWindow ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        finish(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<ASAuthorization, Error>) {
        let callback = completion
        completion = nil
        controller = nil
        presentationWindow = nil
        callback?(result)
    }
}

struct AppleAuthorizationWindow: UIViewRepresentable {
    let presenter: AppleAuthorizationPresenter

    func makeUIView(context: Context) -> WindowObserverView {
        let view = WindowObserverView()
        view.isUserInteractionEnabled = false
        view.onWindowChange = { [weak presenter] window in presenter?.window = window }
        return view
    }

    func updateUIView(_ uiView: WindowObserverView, context: Context) {
        presenter.window = uiView.window
    }
}

final class WindowObserverView: UIView {
    var onWindowChange: ((UIWindow?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window)
    }
}
