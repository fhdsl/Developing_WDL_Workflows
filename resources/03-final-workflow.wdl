version 1.0

workflow minidata_test_alignment {
  input {
    # Sample info
    File sampleFastq
    # Reference Genome information
    File ref_fasta
    File ref_fasta_index
    File ref_dict
    File ref_amb
    File ref_ann
    File ref_bwt
    File ref_pac
    File ref_sa
  }

  #  Map reads to reference
  call BwaMem {
    input:
      input_fastq = sampleFastq,
      ref_fasta = ref_fasta,
      ref_fasta_index = ref_fasta_index,
      ref_dict = ref_dict,
      ref_amb = ref_amb,
      ref_ann = ref_ann,
      ref_bwt = ref_bwt,
      ref_pac = ref_pac,
      ref_sa = ref_sa
  }
   
  # Outputs that will be retained when execution is complete
  output {
    File alignedBamSorted = BwaMem.analysisReadySorted
  }

  parameter_meta {
    sampleFastq: "Filepath to sample .fastq"
    ref_fasta: "Filepath to reference genome"
    ref_fasta_index: "Filepath to reference genome index"
    ref_dict: "Filepath to reference genome dictionary"
    ref_amb: "Filepath to reference genome info"
    ref_ann: "Filepath to reference genome info"
    ref_bwt: "Filepath to reference genome info"
    ref_pac: "Filepath to reference genome info"
    ref_sa: "Filepath to reference genome info"
  }
# End workflow
}

task BwaMem {
  input {
    File input_fastq
    File ref_fasta
    File ref_fasta_index
    File ref_dict
    File ref_amb
    File ref_ann
    File ref_bwt
    File ref_pac
    File ref_sa
    Int threads = 16
  }
  
  String base_file_name = basename(input_fastq, ".fastq")
  String ref_fasta_local = basename(ref_fasta)

  command <<<
    set -eo pipefail

    mv "~{ref_fasta}" .
    mv "~{ref_fasta_index}" .
    mv "~{ref_dict}" .
    mv "~{ref_amb}" .
    mv "~{ref_ann}" .
    mv "~{ref_bwt}" .
    mv "~{ref_pac}" .
    mv "~{ref_sa}" .

    bwa mem \
      -p -v 3 -t ~{threads} -M -R '@RG\tID:foo\tSM:foo2' \
      "~{ref_fasta_local}" "~{input_fastq}" > "~{base_file_name}.sam"
    samtools view -1bS -@ 15 -o "~{base_file_name}.aligned.bam" "~{base_file_name}.sam"
    samtools sort -n -@ 15 -o "~{base_file_name}.sorted_query_aligned.bam" "~{base_file_name}.aligned.bam"

  >>>
  output {
    File analysisReadyBam = "~{base_file_name}.aligned.bam"
    File analysisReadySorted = "~{base_file_name}.sorted_query_aligned.bam"
  }
  runtime {
    memory: "48 GB"
    cpu: 16
    docker: "fredhutch/bwa:0.7.17"
    disks: "local-disk 100 SSD"
  }
}