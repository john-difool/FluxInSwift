/**
 * Copyright (c) 2015, Artivisual, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 *
 */

/**
 * Dispatcher is used to broadcast payloads to registered callbacks. This is
 * different from generic pub-sub systems in two ways:
 *
 *   1) Callbacks are not subscribed to particular events. Every payload is
 *      dispatched to every registered callback.
 *   2) Callbacks can be deferred in whole or part until other callbacks have
 *      been executed.
 *
 * For example, consider this hypothetical flight destination form, which
 * selects a default city when a country is selected:
 *
 *  let flightDispatcher = Dispatcher()
 *
 *   // Keeps track of which country is selected
 *   let CountryStore = CountryStore(country: nil)
 *
 *   // Keeps track of which city is selected
 *   let CityStore = CityStore(city: nil)
 *
 *   // Keeps track of the base flight price of the selected city
 *   let FlightPriceStore = FlightPriceStore(price: null)
 *
 * When a user changes the selected city, we dispatch the payload:
 *
 *   flightDispatcher.dispatch(
 *     "actionType": "city-update",
 *     "selectedCity": "paris"
 *   })
 *
 * This payload is digested by `CityStore`:
 *
 *   flightDispatcher.register { payload in
 *     if payload[actionType] == "city-update" {
 *       CityStore.city = payload["selectedCity"]
 *     }
 *   }
 *
 * When the user selects a country, we dispatch the payload:
 *
 *   flightDispatcher.dispatch({
 *     "actionType": "country-update",
 *     "selectedCountry": "australia"
 *   })
 *
 * This payload is digested by both stores:
 *
 *   CountryStore.dispatchToken = flightDispatcher.register { payload in
 *     if payload["actionType"] == "country-update" {
 *       CountryStore.country = payload["selectedCountry"]
 *     }
 *   }
 *
 * When the callback to update `CountryStore` is registered, we save a reference
 * to the returned token. Using this token with `waitFor()`, we can guarantee
 * that `CountryStore` is updated before the callback that updates `CityStore`
 * needs to query its data.
 *
 *   CityStore.dispatchToken = flightDispatcher.register { payload in
 *     if payload["actionType"] == "country-update" {
 *       // `CountryStore.country` may not be updated.
 *       flightDispatcher.waitFor([CountryStore.dispatchToken])
 *       // `CountryStore.country` is now guaranteed to be updated.
 *
 *       // Select the default city for the new country
 *       CityStore["city"] = getDefaultCityForCountry(CountryStore.country)
 *     }
 *   }
 *
 * The usage of `waitFor()` can be chained, for example:
 *
 *   FlightPriceStore.dispatchToken =
 *     flightDispatcher.register { payload in
 *       switch payload["actionType"] {
 *         case "country-update", "city-update':
 *           flightDispatcher.waitFor([CityStore.dispatchToken])
 *           FlightPriceStore.price =
 *             getFlightPriceStore(CountryStore.country, CityStore.city)
 *       }
 *     }
 *   }
 *
 * The `country-update` payload will be guaranteed to invoke the stores'
 * registered callbacks in order: `CountryStore`, `CityStore`, then
 * `FlightPriceStore`.
 */

enum DispatchError:ErrorType {
    case MissingCallback
}


typealias CBType = ([String:AnyObject]) throws -> Void

class Dispatcher {
    
    private let _prefix = "ID_"

    private var _lastID = 1
    private var _callbacks = [String:CBType]()
    private var _isPending = [String:Bool]()
    private var _isHandled = [String:Bool]()
    private var _isDispatching = false
    private var _pendingPayload: [String:AnyObject]?
    
    /**
      * Registers a callback to be invoked with every dispatched payload. Returns
      * a token that can be used with `waitFor()`.
      *
      */
    func register(callback: CBType) -> String {
        let id = _prefix + String(self._lastID++)
        self._callbacks[id] = callback
        return id
    }
    
    /**
     * Removes a callback based on its token.
     *
     */
    func unregister(id: String) throws {
        try invariant(
            self._callbacks[id] != nil,
            "Dispatcher.unregister(...): `\(id)` does not map to a registered callback.")
        self._callbacks[id] = nil
    }

    /**
      * Waits for the callbacks specified to be invoked before continuing execution
      * of the current callback. This method should only be used by a callback in
      * response to a dispatched payload.
      *
      */
    func waitFor(ids: [String]) throws {
        try invariant(
            self._isDispatching,
            "Dispatcher.waitFor(...): Must be invoked while dispatching."
        )
        for id in ids {
            try invariant(
                self._callbacks[id] != nil,
                "Dispatcher.waitFor(...): `\(id)` does not map to a registered callback."
            )
            if self._isPending[id]! {
                try invariant(
                    self._isHandled[id]!,
                    "Dispatcher.waitFor(...): Circular dependency detected while " +
                    "waiting for `\(id)`."
                )
                continue
            }
            try self._invokeCallback(id)
        }
    }

    /**
     * Dispatches a payload to all registered callbacks.
     *
     */
    func dispatch(payload: [String:AnyObject]) throws {
        try invariant(
            !self._isDispatching,
            "Dispatch.dispatch(...): Cannot dispatch in the middle of a dispatch."
        )
        self._startDispatching(payload)
        defer {
            self._stopDispatching()
        }
        do {
            for (id, _) in self._callbacks {
                if self._isPending[id]! {
                    continue
                }
                try self._invokeCallback(id)
            }
        } catch {
            throw DispatchError.MissingCallback
        }
    }

    /**
     * Is this Dispatcher currently dispatching.
     *
     */
    func isDispatching() -> Bool {
        return self._isDispatching
    }

    /**
     * Call the callback stored with the given id. Also do some internal
     * bookkeeping.
     *
     */
    private func _invokeCallback(id: String) throws {
        self._isPending[id] = true
        if let callback = self._callbacks[id] {
            try callback(self._pendingPayload!)
        } else {
            throw DispatchError.MissingCallback
        }
        self._isHandled[id] = true
    }

    /**
     * Set up bookkeeping needed when dispatching.
     *
     */
    private func _startDispatching(payload: [String:AnyObject]) {
        for (id, _) in self._callbacks {
            self._isPending[id] = false
            self._isHandled[id] = false
        }
        self._pendingPayload = payload
        self._isDispatching = true
    }

    /**
     * Clear bookkeeping used for dispatching.
     *
     */
    private func _stopDispatching() {
        self._pendingPayload = nil
        self._isDispatching = false
    }
}
