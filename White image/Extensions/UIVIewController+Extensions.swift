//
//  UIVIewController+Extensions.swift
//  White image
//
//  Created by Marek Slaninka on 06/10/2023.
//

import UIKit

public extension UIAlertController {
    @discardableResult
    class func showInfoAlert(_ title: String?, message: String?, cancelButtonText: String?, presentingViewController: UIViewController, handler: ((UIAlertAction) -> Swift.Void)? = nil) -> UIAlertController {
        let alert = UIAlertController(title: title, message: message, preferredStyle: UIAlertController.Style.alert)
        
        alert.view.accessibilityIdentifier = "dialog"
        
        if cancelButtonText != nil {
            alert.addAction(UIAlertAction(title: cancelButtonText, style: .cancel, handler: handler))
        }
        
        presentingViewController.present(alert, animated: true, completion: nil)
        
        return alert
    }
}
