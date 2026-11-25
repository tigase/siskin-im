//
//  SceneDelegate.swift
//  SiskinIM
//
//  Created by work on 24/11/2026.
//  Copyright © 2026 Tigase, Inc. All rights reserved.
//


import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    private var appDelegate: AppDelegate? {
        UIApplication.shared.delegate as? AppDelegate
    }

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let window = window else { return }
        appDelegate?.window = window
        appDelegate?.configureInitialInterface()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        appDelegate?.applicationWillEnterForeground(UIApplication.shared)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        appDelegate?.applicationDidBecomeActive(UIApplication.shared)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        appDelegate?.applicationDidEnterBackground(UIApplication.shared)
    }
}
