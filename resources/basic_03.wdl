version 1.0

task do_something {
    input {
        File fastq
        String basename_of_fq
    }
    command <<<
        echo "First ten lines of ~{basename_of_fq}: "
        head ~{fastq}
    >>>
}

workflow my_workflow {
    input {
        File fq
    }
    
    String basename_of_fq = basename(fq)
    
    call do_something {
        input:
            fastq = fq,
            basename_of_fq = basename_of_fq
    }
}