
enum Error:ErrorType {
    case InvariantViolation
}

func invariant(@autoclosure predicate :  () -> Bool, _ message: String = "") throws {
    if !predicate() {
        throw Error.InvariantViolation
    }
}