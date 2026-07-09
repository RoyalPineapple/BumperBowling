func concurrentMap<Element: Sendable, Value: Sendable>(
    _ elements: [Element],
    maxConcurrentJobs: Int? = nil,
    transform: @escaping @Sendable (Element) async -> Value
) async -> [Value] {
    let limit = Swift.max(1, maxConcurrentJobs ?? elements.count)
    return await withTaskGroup(of: Value.self) { group in
        var iterator = elements.makeIterator()
        var runningCount = 0

        while runningCount < limit, let element = iterator.next() {
            runningCount += 1
            group.addTask {
                await transform(element)
            }
        }

        var values: [Value] = []
        while let value = await group.next() {
            values.append(value)
            if let element = iterator.next() {
                group.addTask {
                    await transform(element)
                }
            } else {
                runningCount -= 1
                if runningCount == 0 {
                    break
                }
            }
        }
        return values
    }
}
