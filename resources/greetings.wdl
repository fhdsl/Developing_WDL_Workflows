version 1.0

task greet {
    input {
        String user
    }
    command <<<
        echo "Hello ~{user}!" > greets.txt
    >>>
    output {
        String greeting = read_string("greets.txt")
    }
}

workflow my_workflow {
    input {
        String username
    }
    call greet {
        input:
            user = username
    }
}