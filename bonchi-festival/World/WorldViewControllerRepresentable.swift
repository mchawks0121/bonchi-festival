//
//  WorldViewControllerRepresentable.swift
//  bonchi-festival
//
//  SwiftUI wrapper for WorldViewController.
//  Present this view to turn the current device into the projector display.
//

import SwiftUI
import UIKit

/// Wraps the UIKit `WorldViewController` so it can be pushed onto a SwiftUI
/// navigation stack or presented full-screen from `ContentView`.
struct WorldViewControllerRepresentable: UIViewControllerRepresentable {

    func makeUIViewController(context: Context) -> WorldViewController {
        WorldViewController()
    }

    func updateUIViewController(_ uiViewController: WorldViewController, context: Context) {}
}
