//
//  BolusProgressTableViewCell.swift
//  LoopUI
//
//  Created by Pete Schwamb on 3/11/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopUI
import HealthKit
import MKRingProgressView


public class BolusProgressTableViewCell: UITableViewCell {
    @IBOutlet weak var progressLabel: UILabel!

    @IBOutlet weak var stopSquare: UIView! {
        didSet {
            stopSquare.layer.cornerRadius = 2
        }
    }

    @IBOutlet weak var progressIndicator: RingProgressView!

    public var totalUnits: Double? {
        didSet {
            updateProgress()
        }
    }

    public var deliveredUnits: Double? {
        didSet {
            updateProgress()
        }
    }

    public var unit: HKUnit?

    private lazy var gradient = CAGradientLayer()

    private var doseTotalUnits: Double?

    private var disableUpdates: Bool = false

    lazy var quantityFormatter: QuantityFormatter = {
        let formatter = QuantityFormatter()
        formatter.numberFormatter.minimumFractionDigits = 2
        return formatter
    }()

    override public func awakeFromNib() {
        super.awakeFromNib()

        gradient.frame = bounds
        
        //DarkMode
        NotificationCenter.default.addObserver(self, selector: #selector(darkModeEnabled(_:)), name: .darkModeEnabled, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(darkModeDisabled(_:)), name: .darkModeDisabled, object: nil)
        
        UserDefaults.standard.bool(forKey: "DarkModeEnabled") ?
            NotificationCenter.default.post(name: .darkModeEnabled, object: nil) :
            NotificationCenter.default.post(name: .darkModeDisabled, object: nil)
        //DarkMode

        backgroundView?.layer.insertSublayer(gradient, at: 0)
        updateProgressColor()
    }

    //DarkMode
    @objc func darkModeEnabled(_ notification: Notification) {
        gradient.colors = [UIColor.black.lighter(by: 25)!.cgColor, UIColor.black.lighter(by: 25)!.cgColor]
        progressLabel.textColor = .white
    }
    
    @objc func darkModeDisabled(_ notification: Notification) {
        gradient.colors = [UIColor.white.cgColor, UIColor.cellBackgroundColor.cgColor]
        progressLabel.textColor = .black
    }
    //DarkMode

    override public func layoutSubviews() {
        super.layoutSubviews()

        gradient.frame = bounds
    }

    public override func tintColorDidChange() {
        super.tintColorDidChange()
        updateProgressColor()
    }

    private func updateProgressColor() {
        progressIndicator.startColor = tintColor
        progressIndicator.endColor = tintColor
        stopSquare.backgroundColor = tintColor
    }

    private func updateProgress() {
        guard !disableUpdates, let totalUnits = totalUnits, let unit = unit else {
            return
        }

        let totalUnitsQuantity = HKQuantity(unit: unit, doubleValue: totalUnits)
        let totalUnitsString = quantityFormatter.string(from: totalUnitsQuantity, for: unit) ?? ""

        if let deliveredUnits = deliveredUnits {
            let deliveredUnitsQuantity = HKQuantity(unit: unit, doubleValue: deliveredUnits)
            let deliveredUnitsString = quantityFormatter.string(from: deliveredUnitsQuantity, for: unit) ?? ""

            progressLabel.text = String(format: NSLocalizedString("Bolused %1$@ of %2$@", comment: "The format string for bolus progress. (1: delivered volume)(2: total volume)"), deliveredUnitsString, totalUnitsString)

            let progress = deliveredUnits / totalUnits
            UIView.animate(withDuration: 0.3) {
                self.progressIndicator.progress = progress
            }
        } else {
            progressLabel.text = String(format: NSLocalizedString("Bolusing %1$@", comment: "The format string for bolus in progress showing total volume. (1: total volume)"), totalUnitsString)
        }
    }

    override public func prepareForReuse() {
        super.prepareForReuse()
        disableUpdates = true
        deliveredUnits = 0
        disableUpdates = false
        progressIndicator.progress = 0
        CATransaction.flush()
        progressLabel.text = ""
    }
}

extension BolusProgressTableViewCell: NibLoadable { }
