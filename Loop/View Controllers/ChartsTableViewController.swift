//
//  ChartsTableViewController.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopUI
import HealthKit
import os.log


enum RefreshContext {
    /// Catch-all for lastLoopCompleted, recommendedTempBasal, lastTempBasal, preferences
    case status

    case glucose
    case insulin
    case carbs
    case targets

    case size(CGSize)
}

extension RefreshContext: Hashable {
    var hashValue: Int {
        switch self {
        case .status:
            return 1
        case .glucose:
            return 2
        case .insulin:
            return 3
        case .carbs:
            return 4
        case .targets:
            return 5
        case .size:
            // We don't use CGSize in our determination of hash nor equality
            return 6
        }
    }

    static func ==(lhs: RefreshContext, rhs: RefreshContext) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }
}

extension Set where Element == RefreshContext {
    /// Returns the size value in the set if one exists
    var newSize: CGSize? {
        guard let index = index(of: .size(.zero)),
            case .size(let size) = self[index] else
        {
            return nil
        }

        return size
    }

    /// Removes and returns the size value in the set if one exists
    ///
    /// - Returns: The size, if contained
    mutating func removeNewSize() -> CGSize? {
        guard case .size(let newSize)? = remove(.size(.zero)) else {
            return nil
        }

        return newSize
    }
}


/// Abstract class providing boilerplate setup for chart-based table view controllers
class ChartsTableViewController: UITableViewController, UIGestureRecognizerDelegate {

    private let log = OSLog(category: "ChartsTableViewController")

    //DarkMode
    var darkMode = (UIApplication.shared.delegate as! AppDelegate).darkMode
    let notificationCenter = NotificationCenter.default
    //DarkMode
    
    override func viewDidLoad() {
        super.viewDidLoad()

        if let unit = self.deviceManager.loopManager.glucoseStore.preferredUnit {
            self.charts.glucoseUnit = unit
        }

        let notificationCenter = NotificationCenter.default
        notificationObservers += [
            notificationCenter.addObserver(forName: .UIApplicationDidEnterBackground, object: UIApplication.shared, queue: .main) { [weak self] _ in
                self?.active = false
            },
            notificationCenter.addObserver(forName: .UIApplicationDidBecomeActive, object: UIApplication.shared, queue: .main) { [weak self] _ in
                self?.active = true
            }
        ]

        //DarkMode
        notificationCenter.addObserver(self, selector: #selector(darkModeEnabled(_:)), name: .darkModeEnabled, object: nil)
        notificationCenter.addObserver(self, selector: #selector(darkModeDisabled(_:)), name: .darkModeDisabled, object: nil)
        //DarkMode
        
        let gestureRecognizer = UILongPressGestureRecognizer()
        gestureRecognizer.delegate = self
        gestureRecognizer.minimumPressDuration = 0.1
        gestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
        charts.gestureRecognizer = gestureRecognizer
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()

        if !visible {
            charts.didReceiveMemoryWarning()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        //DarkMode
        darkMode = (UIApplication.shared.delegate as! AppDelegate).darkMode
        notificationCenter.post(name: darkMode ? .darkModeEnabled : .darkModeDisabled, object: nil)
        //DarkMode
        
        visible = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        visible = false
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        log.debug("[reloadData] for view transition to size: %@", String(describing: size))
        reloadData(animated: false)
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - State

    weak var deviceManager: DeviceDataManager! {
        didSet {
            NotificationCenter.default.addObserver(self, selector: #selector(unitPreferencesDidChange(_:)), name: .HKUserPreferencesDidChange, object: deviceManager.loopManager.glucoseStore.healthStore)
        }
    }

    @objc private func unitPreferencesDidChange(_ note: Notification) {
        DispatchQueue.main.async {
            if let unit = self.deviceManager.loopManager.glucoseStore.preferredUnit {
                let didChange = unit != self.charts.glucoseUnit
                self.charts.glucoseUnit = unit

                if didChange {
                    self.glucoseUnitDidChange()
                }
            }
            self.log.debug("[reloadData] for HealthKit unit preference change")
            self.reloadData()
        }
    }

    func glucoseUnitDidChange() {
        // To override.
    }

    let charts = StatusChartsManager(colors: .default, settings: .default)

    // References to registered notification center observers
    var notificationObservers: [Any] = []

    var active: Bool {
        get {
            return UIApplication.shared.applicationState == .active
        }
        set {
            log.debug("[reloadData] for app change to active: %d", active)
            reloadData()
        }
    }

    var visible = false {
        didSet {
            log.debug("[reloadData] for view change to visible: %d", visible)
            reloadData()
        }
    }

    // MARK: - Data loading

    /// Refetches all data and updates the views. Must be called on the main queue.
    ///
    /// - Parameters:
    ///   - animated: Whether the updating should be animated if possible
    func reloadData(animated: Bool = false) {

    }

    // MARK: - UIGestureRecognizer

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        /// Only start the long-press recognition when it starts in a chart cell
        let point = gestureRecognizer.location(in: tableView)
        if let indexPath = tableView.indexPathForRow(at: point) {
            if let cell = tableView.cellForRow(at: indexPath), cell is ChartTableViewCell {
                return true
            }
        }

        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    @objc func handlePan(_ gestureRecognizer: UIGestureRecognizer) {
        switch gestureRecognizer.state {
        case .possible, .changed:
            // Follow your dreams!
            break
        case .began, .cancelled, .ended, .failed:
            for case let row as ChartTableViewCell in self.tableView.visibleCells {
                let forwards = gestureRecognizer.state == .began
                UIView.animate(withDuration: forwards ? 0.2 : 0.5, delay: forwards ? 0 : 1, animations: {
                    let alpha: CGFloat = forwards ? 0 : 1
                    row.titleLabel?.alpha = alpha
                    row.subtitleLabel?.alpha = alpha
                })
            }
        }
    }
    
    ////DarkMode
    // MARK: - Theme
    
    @objc func darkModeEnabled(_ notification: Notification) {
        enableDarkMode()
        self.tableView.reloadData()
    }
    
    @objc func darkModeDisabled(_ notification: Notification) {
        disableDarkMode()
        self.tableView.reloadData()
    }
    
    private func enableDarkMode() {
        self.view.backgroundColor = UIColor.black
        self.tableView.backgroundColor = UIColor.black
        self.navigationController?.navigationBar.barStyle = .blackTranslucent
        self.navigationController?.view.backgroundColor = UIColor.black
    }
    
    private func disableDarkMode() {
        self.view.backgroundColor = UIColor.white
        self.tableView.backgroundColor = UIColor.white
        self.navigationController?.navigationBar.barStyle = .default
        self.navigationController?.view.backgroundColor = UIColor.white
    }
    
    // MARK: - Table view data source
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        
        if darkMode {
            cell.textLabel?.textColor = UIColor.white
            cell.detailTextLabel?.textColor = UIColor.white
            cell.backgroundColor = UIColor.black.lighter(by: 25)
        }
        else {
            cell.textLabel?.textColor = UIColor.black
            cell.detailTextLabel?.textColor = UIColor.black
            cell.backgroundColor = UIColor.white
        }
    }
    //DarkMode

}