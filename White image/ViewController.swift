//
//  ViewController.swift
//  White image
//
//  Created by Marek Slaninka on 06/10/2023.
//

import UIKit

class ViewController: UIViewController {
    @IBOutlet weak var originalImageView: UIImageView!
    @IBOutlet weak var compressedImageView: UIImageView!
    
    lazy var slFileManager: SLFileManager = SLFileManager(viewController: self)
    lazy var activityIndicator: UIActivityIndicatorView = {
        let actInd = UIActivityIndicatorView()
        actInd.style = UIActivityIndicatorView.Style.large
        actInd.backgroundColor = .gray
        actInd.color = .white
        actInd.layer.cornerRadius = 10
        actInd.startAnimating()
        actInd.translatesAutoresizingMaskIntoConstraints = false

        return actInd
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

    @IBAction func takePhoto(_ sender: Any) {
        slFileManager.loadImage(sender: self) {
            self.showLoading()
        }  didProcessFile: { result in
            self.hideLoading()
            switch result {
                case .success(let data):
                    self.originalImageView.image = data.image
                    self.compressedImageView.image = UIImage(data: data.data)
                case .failure(let error):
                    debugPrint(error)
            }
        }

    }
    
    func showLoading() {
        self.view.addSubview(activityIndicator)
        activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        activityIndicator.widthAnchor.constraint(equalToConstant: 100).isActive = true
        activityIndicator.heightAnchor.constraint(equalToConstant: 100).isActive = true
    }
    
    func hideLoading() {
        self.activityIndicator.removeFromSuperview()
    }
    
}

