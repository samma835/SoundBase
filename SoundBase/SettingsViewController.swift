//
//  SettingsViewController.swift
//  SoundBase
//
//  Created by samma on 2026/1/22.
//

import UIKit
import SnapKit

class SettingsViewController: UIViewController {
    
    private lazy var placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = "设置功能开发中..."
        label.font = .systemFont(ofSize: 16)
        label.textColor = .systemGray
        label.textAlignment = .center
        return label
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        title = "设置"
        view.backgroundColor = .systemBackground
        
        view.addSubview(placeholderLabel)
        
        placeholderLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }
}
