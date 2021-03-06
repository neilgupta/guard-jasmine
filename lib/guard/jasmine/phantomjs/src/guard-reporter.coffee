# Capture statements that were logged to the console
# during spec execution.
#
# To do so it substitues it's own functions for the console.<levels>
#
extendObject = (a, b)->
    for key,value of b
        a[key] = value if b.hasOwnProperty(key)
    return a

isObject =(obj)->
    type = typeof obj;
    return type == 'function' || type == 'object' && !!obj;

isFunction = (obj)->
    return typeof obj == 'function' || false;


class ConsoleCapture
    # Instead of attempting to de-activate the console dot reporter in hacky ways,
    # just ignore it's output
    @DOT_REPORTER_MATCH = /\[\d+m[F.]..0m/
    @levels: ['log','info','warn','error','debug' ]
    @original = console

    @original_levels = {}
    @original_levels[level] = console[level] for level in ConsoleCapture.levels

    constructor:->
        @original = {}
        @captured = []
        this._reassign_level( level ) for level in ConsoleCapture.levels

    revert: ->
        for level in ConsoleCapture.levels
            ConsoleCapture.original[level] = ConsoleCapture.original_levels[level]

    _reassign_level: ( level )->
        my = this
        console[level] = ->
            args = Array.prototype.slice.call(arguments, 0)
            return if args[0] &&
                args[0].toString &&
                args[0].toString().match( ConsoleCapture.DOT_REPORTER_MATCH )
            my.captured.push( [ level ].concat( args ) )
            ConsoleCapture.original_levels[ level ].apply( ConsoleCapture.original, arguments )

# Implements a Jasmine reporter
class GuardReporter
    @STACK_MATCHER=new RegExp("__spec__\/(.*):([0-9]+)","g")

    jasmineStarted: ->
        @console = new ConsoleCapture();
        @startedAt = Date.now()
        @currentSuite = { suites: [] }
        @stack     = [ @currentSuite ]

    suiteStarted: (suite)->
        suite = extendObject({ specs: [], suites: [] }, suite )
        @currentSuite.suites.push( suite )
        @currentSuite = suite
        @stack.push(suite)

    suiteDone: (Suite)->
        @stack.pop()
        @currentSuite = @stack[@stack.length-1]

    jasmineDone: ->
        @resultComplete = true

    specDone: (spec)->
        @resultReceived = true
        spec = extendObject({ logs: @console.captured, errors: [] }, spec )
        for failure in spec.failedExpectations||[]
            error = extendObject({trace:[]}, failure )
            while match = GuardReporter.STACK_MATCHER.exec( failure.stack )
                error.trace.push({ file: match[1], line: parseInt(match[2]) })
            delete error.stack
            this.stringifyExpection(error)
            spec.errors.push( error )
        delete spec.failedExpectations
        this.stringifyExpection(success) for success in spec.passedExpectations||[]
        @currentSuite.specs.push( spec )
        this.resetConsoleLog()
        spec

    # if the expected object is very large, we don't want to
    # include it in the JSON reply.  For instance a DOM Element
    # will actually end up including the entire page (including script source)
    stringifyExpection: (expected)->
        for key in ['actual','expected']
            if isFunction(expected[key])
                expected[key] = expected[key].name || "function"
            else if isObject(expected[key])
                expected[key] = expected[key].toString()

    resetConsoleLog: ->
        @console.revert()
        @console = new ConsoleCapture

    eachSuite: (suite)->
        suites = [].concat( suite.suites )
        for suite in suite.suites
            suites = suites.concat( this.eachSuite(suite) )
        suites

    results: ->
        stats = {
            time     : ( Date.now() - @startedAt ) / 1000
            specs    : 0
            failed   : 0
            pending  : 0
            disabled : 0
        }
        for suite in this.eachSuite(@stack[0])
            stats.specs += suite.specs.length
            for spec in suite.specs
                stats[spec.status] += 1 unless undefined == stats[spec.status]
        {
            jasmine_version: jasmine?.version
            stats: stats
            suites: @stack[0].suites
        }

if typeof module isnt 'undefined' and module.exports
    module.exports = GuardReporter
else
    window.GuardReporter = GuardReporter
