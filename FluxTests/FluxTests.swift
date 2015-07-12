import XCTest

class FluxTests: XCTestCase {
    
    var dispatcher = Dispatcher()
    
    var callbackA_mock_calls: [[String : AnyObject]]?
    var callbackB_mock_calls: [[String : AnyObject]]?

    func callbackA(payload: [String : AnyObject]) throws {
        callbackA_mock_calls!.append(payload)
    }
    
    func callbackB(payload: [String : AnyObject]) throws {
        callbackB_mock_calls!.append(payload)
    }
    
    var tokenA: String?
    var tokenB: String?
    

    override func setUp() {
        super.setUp()
        callbackA_mock_calls = [[String : AnyObject]]()
        callbackB_mock_calls = [[String : AnyObject]]()
    }
    
    override func tearDown() {
        callbackA_mock_calls = nil
        callbackB_mock_calls = nil
        super.tearDown()
    }
    
    func compareAddresses(o1: AnyObject, _ o2: AnyObject) -> Bool {
        return unsafeAddressOf(o1) == unsafeAddressOf(o2)
    }
    
    func testShouldExecuteAllSubscriberCallbacks() {
        
        dispatcher.register(callbackA)
        dispatcher.register(callbackB)
            
        let payload = [String : AnyObject]()
        try! dispatcher.dispatch(payload)
            
        XCTAssertEqual(callbackA_mock_calls!.count, 1)
        XCTAssert(compareAddresses(callbackA_mock_calls![0], payload))
        
        XCTAssertEqual(callbackB_mock_calls!.count, 1)
        XCTAssert(compareAddresses(callbackB_mock_calls![0], payload))
        
        try! dispatcher.dispatch(payload)
            
        XCTAssertEqual(callbackA_mock_calls!.count, 2)
        XCTAssert(compareAddresses(callbackA_mock_calls![1], payload))
        
        XCTAssertEqual(callbackB_mock_calls!.count, 2)
        XCTAssert(compareAddresses(callbackB_mock_calls![1], payload))

    }
    
    func testShouldWaitForCallbacksRegisteredEarlier() {

        let tokenA = dispatcher.register(callbackA)
    
        dispatcher.register { payload throws in
            try self.dispatcher.waitFor([tokenA])
            XCTAssertEqual(self.callbackA_mock_calls!.count, 1)
            XCTAssert(self.compareAddresses(self.callbackA_mock_calls![0], payload))
            try self.callbackB(payload)
        }
    
        let payload = [String : AnyObject]()
        try! dispatcher.dispatch(payload)
    
        XCTAssertEqual(callbackA_mock_calls!.count, 1)
        XCTAssert(compareAddresses(callbackA_mock_calls![0], payload))
    
        XCTAssertEqual(callbackB_mock_calls!.count, 1)
        XCTAssert(compareAddresses(callbackB_mock_calls![0], payload))
    }

    func testShouldThrowIfDispatchWhileDispatching() {
        dispatcher.register { payload throws in
            try self.dispatcher.dispatch(payload)
            try self.callbackA(payload)
        }
    
        let payload = [String : AnyObject]()
        do {
            try dispatcher.dispatch(payload)
            XCTAssert(false)
        } catch {
        }
    
        XCTAssertEqual(callbackA_mock_calls!.count, 0)
    }
    
    func testShouldThrowIfWaitForWhileNotDispatching() {
        let tokenA = dispatcher.register(callbackA)
    
        do {
            try dispatcher.waitFor([tokenA])
            XCTAssert(false)
        } catch {
        }
    
        XCTAssertEqual(callbackB_mock_calls!.count, 0)
    }
    
    func testShouldThrowIfWaitForWithInvalidToken() {
        let invalidToken = "1337"
    
        dispatcher.register { payload throws in
            try self.dispatcher.waitFor([invalidToken])
        }
    
        let payload = [String : AnyObject]()
        
        do {
            try dispatcher.dispatch(payload)
            XCTAssert(false)
        } catch {
        }
    }
    
    func testThrowOnSelfCircularDependencies() {
        
        tokenA = dispatcher.register { payload throws in
            try self.dispatcher.waitFor([self.tokenA!])
            try self.callbackA(payload)
        }
    
        let payload = [String : AnyObject]()
        do {
            try dispatcher.dispatch(payload)
            XCTAssert(false)
        } catch {
        }
        
        XCTAssertEqual(callbackA_mock_calls!.count, 0)
    }
    
    func testThrowOnMultiCircularDependencies() {
        
        tokenA = dispatcher.register { payload throws in
            try self.dispatcher.waitFor([self.tokenB!])
            try self.callbackA(payload)
        }
        
        tokenB = dispatcher.register { payload throws in
            try self.dispatcher.waitFor([self.tokenA!])
            try self.callbackB(payload)
        }
        
        let payload = [String : AnyObject]()
        do {
            try dispatcher.dispatch(payload)
            XCTAssert(false)
        } catch {
        }
        
        XCTAssertEqual(callbackA_mock_calls!.count, 0)
        XCTAssertEqual(callbackB_mock_calls!.count, 0)
    }
    
    func testRemainInAConsistentStateAfterAFailedDispatch() {
        dispatcher.register(callbackA)

        dispatcher.register { payload throws in
            if let value = payload["shouldThrow"] as? Bool where value {
                throw DispatchError.MissingCallback
            }
            try self.callbackB(payload)
        }
    
        do {
            try dispatcher.dispatch(["shouldThrow": true])
            XCTAssert(false)
        } catch {
        }

    
        // Cannot make assumptions about a failed dispatch.
        let callbackACount = callbackA_mock_calls!.count
        
        try! dispatcher.dispatch(["shouldThrow": false])
        
        XCTAssertEqual(callbackA_mock_calls!.count, callbackACount + 1)
        XCTAssertEqual(callbackB_mock_calls!.count, 1)

    }
    
    func testIfProperlyUnregisterCallbacks() {
        dispatcher.register(callbackA)
    
        let tokenB = dispatcher.register(callbackB)
    
        let payload = [String : AnyObject]()
        try! dispatcher.dispatch(payload)

        XCTAssertEqual(callbackA_mock_calls!.count, 1)
        XCTAssert(compareAddresses(callbackA_mock_calls![0], payload))

        XCTAssertEqual(callbackB_mock_calls!.count, 1)
        XCTAssert(compareAddresses(callbackB_mock_calls![0], payload))

        try! dispatcher.unregister(tokenB)

        try! dispatcher.dispatch(payload)

        XCTAssertEqual(callbackA_mock_calls!.count, 2)
        XCTAssert(compareAddresses(callbackA_mock_calls![0], payload))

        XCTAssertEqual(callbackB_mock_calls!.count, 1)
    }
}
