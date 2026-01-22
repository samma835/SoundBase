//
//  ViewController.swift
//  SoundBase
//
//  Created by samma on 2026/1/22.
//

import UIKit
import SnapKit

class ViewController: UIViewController {

    private lazy var startButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("开始搜索YouTube音频", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        button.addTarget(self, action: #selector(startButtonTapped), for: .touchUpInside)
        return button
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        title = "SoundBase"
        view.backgroundColor = .systemBackground
        
        view.addSubview(startButton)
        
        startButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(240)
            make.height.equalTo(50)
        }
    }
    
    @objc private func startButtonTapped() {
        let searchVC = YouTubeSearchViewController()
        let navController = UINavigationController(rootViewController: searchVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
}

