//
//  Int+Extensions.swift
//  GSPlayer
//
//  Created by Gesen on 2019/4/21.
//  Copyright © 2019 Gesen. All rights reserved.
//

import Foundation

extension Int {
    
    var double: Double {
        return Double(self)
    }
    
}

extension Int64 {

    var double: Double {
        return Double(self)
    }

    func parseCount() -> String {
        if self < 1000 {
            return String(format: "%d", self)
        } else if self < 1000000 {
            return String(format: "%dK", self / 1000)
        } else if self < 1000000000 {
            return String(format: "%dM", self / 1000000)
        } else {
            return String(format: "%dB", self / 1000000000)
        }
    }
}
