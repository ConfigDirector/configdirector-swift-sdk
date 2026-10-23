import ConfigDirector

/// A config value a test client serves: the SDK's `ServedValue`, under the name tests have always
/// used. The config type follows from the case: a boolean, integer, float, or string config, or a
/// JSON config for an object or an array.
///
/// Values are usually written as literals rather than spelled out:
///
/// ```swift
/// let testClient = makeTestClient(values: [
///     "new-checkout": true,
///     "max-items": 20,
///     "discount": 0.15,
///     "greeting": "hello",
///     "theme": ["color": "blue", "radius": 8],
///     "tags": ["a", "b"],
/// ])
/// ```
///
/// A string is always a string config, so JSON text meant as a JSON config is given as an object
/// or an array. There is no null case; use ``TestClient/removeValue(for:)`` to remove a value.
public typealias TestValue = ServedValue
