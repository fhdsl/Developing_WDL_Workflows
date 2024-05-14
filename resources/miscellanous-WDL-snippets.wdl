version 1.0

task do_something_curly_braces {
  input {
    String some_string
  }
  command {
    some_other_string="FOO"
    echo ${some_string}
    echo $some_other_string
  }
}

task do_something_carrots {
  input {
    String some_string
  }
  command <<<
    some_other_string="FOO"
    echo ~{some_string}
    echo $some_other_string
  >>>
}

task cowsay {
  input {
    String some_string
  }
  command <<<
    cowsay -t "~{some_string}"
  >>>
  runtime {
    docker: "koyeb/cowsay:latest"
  }
}

task count_words {
  input {
    Array[String] a_big_sentence
  }
  command <<<
    ARRAY_OF_WORDS=(~{sep=" " a_big_sentence})
    echo ${#ARRAY_OF_FILES[@]} >> length.txt
    # Note how the bash array uses ${} syntax, which could quickly get
    # confusing if we used that syntax for our WDL variables. This is
    # why we recommend using tilde + {} for your WDL variables.
  >>>
}

task count_words_python {
  input {
    Array[String] a_big_sentence
  }
  command <<<
    python << CODE
    sentence = [ "~{sep='", "' a_big_sentence}" ]
    print(len(sentence))
    CODE
  >>>
  runtime {
    docker: "python:latest"
  }
}

task bam_to_sam {
  input {
    File input_bam
  }
  command <<<
    samtools view -1bS -@ 15 -o converted.sam ~{input_bam}
  >>>
  runtime {
    cpu: 16
    docker: "fredhutch/bwa:0.7.17"
    memory: "48 GB"
  }
  output {
    File sam_file = "converted.sam"
  }
}

task bam_to_sam_in_folder {
  input {
    File input_bam
  }
  command <<<
    mkdir sams
    samtools view -1bS -@ 15 -o converted.sam ~{input_bam}
    mv converted.sam ./sams/converted.sam
  >>>
  runtime {
    cpu: 16
    docker: "fredhutch/bwa:0.7.17"
    memory: "48 GB"
  }
  output {
    File sam_file = "sams/converted.sam"
  }
}

task bam_to_sam_again {
  input {
    File input_bam
  }
  String base_file_name = basename(input_bam, ".bam")
  command <<<
    samtools view -1bS -@ 15 -o ~{base_file_name}.sam ~{input_bam}
  >>>
  runtime {
    cpu: 16
    docker: "fredhutch/bwa:0.7.17"
    memory: "48 GB"
  }
  output {
    File sam_file = base_file_name + ".sam"
  }
}

task add_one {
  input {
    Int some_integer
  }
  command <<<
    echo ~{some_integer} > a.txt
    echo "1" > b.txt
  >>>
  output {
    Int a = read_int("a.txt")
    Int b = read_int("b.txt")
    Int c = a + b
  }
}

workflow test_everything {

    call do_something_curly_braces {
        input:
            some_string = "howdy"
    }
    call do_something_carrots {
        input:
            some_string = "howdy"
    }
    call cowsay {
        input:
            some_string = "hello world"
    }
    call count_words {
        input:
            a_big_sentence = ["What", "is", "the", "airspeed", "velocity",
                            "of", "an", "unladen", "swallow?"]
    }
    call count_words_python {
        input:
            a_big_sentence = ["What", "is", "the", "airspeed", "velocity",
                            "of", "an", "unladen", "swallow?"]
    }
    call add_one {
        input:
            some_integer = 5
    }
}