version 1.0

task do_something {
    input {
        File fastq
        String basename_of_fq
    }
    command <<<
        echo "First ten lines of ~{basename_of_fq}: " >> output.txt
        head ~{fastq} >> output.txt
    >>>
    output {
        File first_ten_lines = "output.txt"
    }
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
    
    output {
        File ten_lines = do_something.first_ten_lines
    }
}