version 1.0

task do_something {
    input {
        File fastq
    }
    command <<<
        exit 0
    >>>
}

workflow my_workflow {
    input {
        File fq
    }
    call do_something {
        input:
            fastq = fq
    }
}