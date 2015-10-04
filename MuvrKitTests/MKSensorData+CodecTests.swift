import Foundation
import XCTest
@testable import MuvrKit

class MKSensorDataCodecTests : XCTestCase {
    
    func testNotEnoughInput() {
        do {
            _ = try MKSensorData(decoding: NSData())
            XCTFail("Not caught")
        } catch MKCodecError.NotEnoughInput {
        } catch {
            XCTFail("Bad exception thrown")
        }
    }
    
    func testMalicious() {
        do {
            _ = try MKSensorData(decoding: "ad\u{01}ssssssssfcccctar.".dataUsingEncoding(NSASCIIStringEncoding)!)
            XCTFail("Not caught")
        } catch MKCodecError.NotEnoughInput {
        } catch {
            XCTFail("Bad exception \(error)")
        }
    }
    
    func testEncodeDecode() {
        let d = try! MKSensorData(
            types: [.Accelerometer(location: .RightWrist), .Accelerometer(location: .LeftWrist),
                    .Gyroscope(location: .RightWrist), .Gyroscope(location: .LeftWrist), .HeartRate],
            start: 0,
            samplesPerSecond: 1,
            samples: [Float](count: 1300, repeatedValue: 0)
        )
        
        let encoded = try! d.encode()
        let dx = try! MKSensorData(decoding: encoded)
        XCTAssertEqual(d, dx)
    }
    
    func testMalformedHeader() {
        do {
            _ = try MKSensorData(decoding: "123456789abcdef10".dataUsingEncoding(NSASCIIStringEncoding)!)
            XCTFail("Not caught")
        } catch MKCodecError.BadHeader {
        } catch {
            XCTFail("Bad exception")
        }
    }

    func testTruncatedInput() {
        let d = try! MKSensorData(
            types: [.HeartRate],
            start: 0,
            samplesPerSecond: 1,
            samples: [Float](count: 100, repeatedValue: 0)
        )
        
        let encoded = try! d.encode()

        do {
            _ = try MKSensorData(decoding: encoded.subdataWithRange(NSRange(location: 0, length: 17)))
            XCTFail("Not caught")
        } catch MKCodecError.NotEnoughInput {
        } catch {
            XCTFail("Bad exception")
        }

        do {
            let wrongData = NSMutableData(data: encoded.subdataWithRange(NSRange(location: 0, length: 16)))
            wrongData.appendData("...".dataUsingEncoding(NSASCIIStringEncoding)!)
            _ = try MKSensorData(decoding: wrongData)
            XCTFail("Not caught")
        } catch MKCodecError.BadHeader {
        } catch {
            XCTFail("Bad exception")
        }
    }

}