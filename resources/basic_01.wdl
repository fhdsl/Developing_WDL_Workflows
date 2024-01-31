version 1.0

task do_something {
    command <<<
        exit 0
    >>>
}

workflow my_workflow {
    call do_something
}