version 1.0

task autoscale_disk_size_for_basically_anything {
    input {
        File ref_genome       # required file
        File? ref_alt         # optional file
        Array[File] fastqs    # required array of files
        File tarball_bams     # uncompressed tarball of bam files
        File compressed_vcfs  # compressed (tar.gz) tarball of VCFs
        Int? addl_disk_gb     # user-defined integer 
    }

    # ref_genome always exists, so we can size() on it safely. size() returns a float,
    # but some backends require disk size is an integer, so we use ceil() to turn
    # that float into an integer. ceil() always rounds up.
    # You should ALWAYS explictly defining which unit you are using with size(). I 
    # recommend sticking with GB. If you do not define a unit, it is easy to accidentally
    # request ludricious amounts of disk space, eg:
    # 1 GB --> 1073741824 bytes --> 1073741824 GB --> 1.07 exabytes
    Int disk_ref = ceil(size(ref_genome, "GB"))

    # ref_alt does not always exist, and size() will break if you try to use it on an
    # undefined file. To prevent this, we use select_first to fall back on the always-
    # defined ref_genome file if ref_alt is undefined.
    Int disk_alt = ceil(size(select_first([ref_alt, ref_genome]), "GB"))

    # Of course, this means that if ref_alt is undefined, then we don't really need 
    # disk_alt, because the size of ref_genome is already covered by disk_ref.
    Int disk_both_refs = if defined(ref_alt) then disk_alt + disk_ref else disk_ref

    # You might be wondering why we don't just do this:
    #     Int disk_alt = if defined(ref_alt) then ceil(size(ref_alt, "GB")) else 0
    # This is synatically valid, but generally speaking it is best to avoid running
    # WDL built-in functions (except select_all, select_first, and defined) on optional
    # variables as much as possible. 

    # When dealing with arrays, size() will return the sum of all Files in the array.
    Int disk_fastqs = ceil(size(fastqs, "GB"))

    # If you are passing in a tarball, you will likely be expanding it. If so, consider
    # doubling the disk size to account for it in both states.
    Int disk_tarball = 2*ceil(size(tarball_bams, "GB"))

    # A compressed tar.gz is harder to predict. As a very rough rule of thumb, 10x should
    # be enough. If you are passing in a tar.gz made from an upstream task, you may want
    # to decrease this number based on the compression ratio you used.
    Int disk_compressed = 10*ceil(size(compressed_vcfs))

    # Because addl_disk_gb is an optional integer with no fallback, you cannot add it to 
    # another integer, eg, this will error as "Non-numeric operand to + operator":
    #    Int final_disk_size = disk_both_refs + disk_fastqs + disk_tarball + disk_compressed + addl_disk_gb
    # We have to use select_first() to coerce it into a not-optional integer first.
    Int disk_addl = select_first([addl_disk_gb, 0])

    # Finally, let's add everything up. (Recall that disk_both_refs accounts for ref_genome and
    # also ref_alt.)
    Int final_disk_size = disk_both_refs + disk_fastqs + disk_tarball + disk_compressed + disk_addl

    command <<<
    echo disk_ref: ~{disk_ref}
    echo disk_alt: ~{disk_alt}
    echo disk_both_refs: ~{disk_both_refs}
    echo disk_fastqs: ~{disk_fastqs}
    echo disk_tarball: ~{disk_tarball}
    echo disk_compressed: ~{disk_compressed}
    echo addl_disk_gb: ~{addl_disk_gb}
    echo final_disk_size: ~{final_disk_size}
    >>>

    runtime {
        # On GCP!Cromwell, if you do not define the units in the runtime attribute, this
        # will be interpreted as the size in GB. This is why it's so easy to accidentally
        # request the wrong amount of disk space if you do not define the units for size();
        # In one place WDL defaults to bytes but in the other it defaults to GB.
        disks: "local-disk " + final_disk_size + " HDD"
    }
}


task do_something {
    input {
        Array[File] some_array_of_files
        File one_file
    }
    
    Int predicted_disk_space = ceil(size(some_array_of_files, "GB")) + ceil(size(one_file, "GB")) + 1
    # size(x, "GB") returns a float representing the size of x in gigabytes
    # ceil() is a WDL built-in function that rounds a float up into an integer
    
    command <<<
    pass
    >>>
    
    runtime {
        docker: "ubuntu-latest"
        disks: "local-disk " + predicted_disk_space + " HDD"
    }
}