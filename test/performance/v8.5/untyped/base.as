// Copyright 2008 the V8 project authors. All rights reserved.
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above
//       copyright notice, this list of conditions and the following
//       disclaimer in the documentation and/or other materials provided
//       with the distribution.
//     * Neither the name of Google Inc. nor the names of its
//       contributors may be used to endorse or promote products derived
//       from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


// Simple framework for running the benchmark suites and
// computing a score based on the timing measurements.


// A benchmark has a name (string) and a function that will be run to
// do the performance measurement. The optional setup and tearDown
// arguments are functions that will be invoked before and after
// running the benchmark, but the running time of these functions will
// not be accounted for in the benchmark score.
class Benchmark {
    public var name;
    public var run;
    public var Setup;
    public var TearDown;
    public function Benchmark(name, run, setup, tearDown) {
        this.name = name;
        this.run = run;
        this.Setup = setup ? setup : new Function();
        this.TearDown = tearDown ? tearDown : new Function();
    }
}


// Benchmark results hold the benchmark and the measured time used to
// run the benchmark. The benchmark score is computed later once a
// full benchmark suite has run to completion.
class BenchmarkResult {
    private var benchmark;
    private var time;
    public function BenchmarkResult(benchmark, time) {
        this.benchmark = benchmark;
        this.time = time;
    }

    // Automatically convert results to numbers. Used by the geometric
    // mean computation.
    public function valueOf() {
      return this.time;
    }
}




// Suites of benchmarks consist of a name and the set of benchmarks in
// addition to the reference timing that the final score will be based
// on. This way, all scores are relative to a reference run and higher
// scores implies better performance.
class BenchmarkSuite {
    
    // Keep track of all declared benchmark suites.
    static var suites = [];

    // Scores are not comparable across versions. Bump the version if
    // you're making changes that will affect that scores, e.g. if you add
    // a new benchmark or change an existing one.
    public var version = '5';
    private var name;
    private var reference;
    private var benchmarks;
    private var results;
    private var runner;
    static private var scores;
    
    public function BenchmarkSuite(name, reference, benchmarks) {
        this.name = name;
        this.reference = reference;
        this.benchmarks = benchmarks;
        BenchmarkSuite.suites.push(this);
    }
    
    // Runs all registered benchmark suites and optionally yields between
    // each individual benchmark to avoid running for too long in the
    // context of browsers. Once done, the final score is reported to the
    // runner.
    public static function RunSuites(runner) {
        var continuation = null;
        var length = suites.length;
        BenchmarkSuite.scores = [];
        var index = 0;
        function RunStep() {
            while (continuation || index < length) {
                if (continuation) {
                    continuation = continuation();
                } else {
                    var suite = suites[index++];
                    if (runner.NotifyStart) runner.NotifyStart(suite.name);
                    continuation = suite.RunStep(runner);
                }
                if (continuation && typeof window != 'undefined' && window.setTimeout) {
                    window.setTimeout(RunStep, 25);
                    return;
                }
            }
            if (runner.NotifyScore) {
                var score = BenchmarkSuite.GeometricMean(BenchmarkSuite.scores);
                var formatted = BenchmarkSuite.FormatScore(100 * score);
                runner.NotifyScore(formatted);
            }
        }
        RunStep();
    }

    // Counts the total number of registered benchmarks. Useful for
    // showing progress as a percentage.
    public function CountBenchmarks() {
        var result = 0;
        for (var i = 0; i < suites.length; i++) {
            result += suites[i].benchmarks.length;
        }
        return result;
    }

    // Computes the geometric mean of a set of numbers.
    public static function GeometricMean (numbers) {
        var log = 0;
        for (var i  = 0; i < numbers.length; i++) {
            log += Math.log(numbers[i]);
        }
        return Math.pow(Math.E, log / numbers.length);
    }

    // Converts a score value to a string with at least three significant
    // digits.
    public static function FormatScore(value) {
        if (value > 100) {
            return value.toFixed(0);
        } else {
            return value.toPrecision(3);
        }
    }

    // Notifies the runner that we're done running a single benchmark in
    // the benchmark suite. This can be useful to report progress.
    public function NotifyStep(result) {
        this.results.push(result);
        if (this.runner.NotifyStep) this.runner.NotifyStep(result.benchmark.name);
    }

    // Notifies the runner that we're done with running a suite and that
    // we have a result which can be reported to the user if needed.
    public function NotifyResult() {
        var mean = BenchmarkSuite.GeometricMean(this.results);
        var score = this.reference / mean;
        BenchmarkSuite.scores.push(score);
        if (this.runner.NotifyResult) {
            var formatted = BenchmarkSuite.FormatScore(100 * score);
            this.runner.NotifyResult(this.name, formatted);
        }
    }


    // Notifies the runner that running a benchmark resulted in an error.
    public function NotifyError(error) {
        if (this.runner.NotifyError) {
            this.runner.NotifyError(this.name, error);
        }
        if (this.runner.NotifyStep) {
            this.runner.NotifyStep(this.name);
        }
    }

    // Runs a single benchmark for at least a second and computes the
    // average time it takes to run a single iteration.
    public function RunSingleBenchmark(benchmark) {
        var elapsed = 0;
        var start = new Date();
        for (var n = 0; elapsed < 1000; n++) {
            benchmark.run();
            elapsed = new Date() - start;
        }
        var usec = (elapsed * 1000) / n;
        this.NotifyStep(new BenchmarkResult(benchmark, usec));
    }

    // This function starts running a suite, but stops between each
    // individual benchmark in the suite and returns a continuation
    // function which can be invoked to run the next benchmark. Once the
    // last benchmark has been executed, null is returned.
    public function RunStep(runner) {
        this.results = [];
        this.runner = runner;
        var length = this.benchmarks.length;
        var index = 0;
        var suite = this;
        function RunNextSetup() {
            if (index < length) {
                try {
                    suite.benchmarks[index].Setup();
                } catch (e) {
                    suite.NotifyError(e);
                    return null;
                }
                return RunNextBenchmark;
            }
            suite.NotifyResult();
            return null;
        }
        
        function RunNextBenchmark() {
            try {
                suite.RunSingleBenchmark(suite.benchmarks[index]);
            } catch (e) {
                suite.NotifyError(e);
                return null;
            }
            return RunNextTearDown;
        }

        function RunNextTearDown() {
            try {
                suite.benchmarks[index++].TearDown();
            } catch (e) {
                suite.NotifyError(e);
                return null;
            }
        return RunNextSetup;
        }

        // Start out running the setup.
        return RunNextSetup();
    }
}

// To make the benchmark results predictable, we replace Math.random
// with a 100% deterministic alternative.
var seed = 49734321;
class Math2 {
    public static function random() {
        // Robert Jenkins' 32 bit integer hash function.
        seed = ((seed + 0x7ed55d16) + (seed << 12))  & 0xffffffff;
        seed = ((seed ^ 0xc761c23c) ^ (seed >>> 19)) & 0xffffffff;
        seed = ((seed + 0x165667b1) + (seed << 5))   & 0xffffffff;
        seed = ((seed + 0xd3a2646c) ^ (seed << 9))   & 0xffffffff;
        seed = ((seed + 0xfd7046c5) + (seed << 3))   & 0xffffffff;
        seed = ((seed ^ 0xb55a4f09) ^ (seed >>> 16)) & 0xffffffff;
        return (seed & 0xfffffff) / 0x10000000;
    }
}


// Functions provided to work in tamarin testing framework
function PrintResult(name, result) {
    print('name '+name);
    print('metric v8 ' + result);
}

function PrintScore(score) {
    print('----');
    print('Score: ' + score);
}
function PrintError(name, err) {
    print("[" +name+ "]: " + err);
}

// Provide an alert() function
function alert(msg){
    print(msg);
}
//Provide load() as a no-op, handled for ASC via dir.asc_args
function load(src){}