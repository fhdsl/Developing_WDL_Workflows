

# Organizing variables via Structs

In our workflow so far, we see that certain variables are always used together, even for different tasks. For example, variables related to the reference genome are always used for the same purpose and passed on to tasks in almost the same way. This leads to quite a bit of coding redundancy, as when we write down the large set of variables related to the reference genome as task inputs, we are just thinking about one entity. We don't make distinctions of the reference genome files until the task body itself.

To improve code organization and readability, we can package all variables related to the reference genome into a compound data structure called a **struct**. With a struct variable, we can refer all the packaged variables as one single variable, and also refer to specific variables within the struct without losing any information. [OpenWDL Docs](https://docs.openwdl.org/en/stable/WDL/using_structs/) also has an excellent introduction and examples on structs.

To define a struct, we must declare it outside of a `workflow` and `task`:

```         
struct referenceGenome {
    File ref_fasta
    File ref_fasta_index
    File ref_dict
    File ref_amb
    File ref_ann
    File ref_bwt
    File ref_pac
    File ref_sa
    String ref_name
}

workflow mutation_calling {
  input {
    File sampleFastq
    referenceGenome refGenome           ## our struct
    ...
  }
    
  # Map reads to reference
  call BwaMem {
    input:
      input_fastq = sampleFastq,
      refGenome = refGenome             ## our struct 
  }
}
  
```

The `referenceGenome` struct contains all the variables related to the reference genome, but values cannot be defined here. The struct definition merely lays the skeleton components of the data structure, but contains no actual values.

In our workflow inputs, we remove all of the `File` variables associated with reference genome definitions, but keep anything that isn't related to the reference genome, such as `sampleFastq`. We instead declare a `referenceGenome` struct variable called `refGenome` via `referenceGenome refGenome`. We can access the variables within a struct by the following syntax: `structVar.varName`, such as `refGenome.ref_name`. The [WDL spec](https://github.com/openwdl/wdl/blob/main/versions/1.0/SPEC.md#struct-definition) has more information on how to define and use structs.

To give values to `refGenome`, we need to modify our JSON metadata file. We define the `refGenome` variable in a nested structure that corresponds to the `referenceGenome` struct. Let's take a look:

```         
{
  "mutation_calling.refGenome": {
    "ref_fasta": "/path/to/Homo_sapiens_assembly19.fasta",
    "ref_fasta_index": "/path/to/Homo_sapiens_assembly19.fasta.fai",
    "ref_dict": "/path/to/Homo_sapiens_assembly19.dict",
    "ref_pac": "/path/to/Homo_sapiens_assembly19.fasta.pac",
    "ref_sa": "/path/to/Homo_sapiens_assembly19.fasta.sa",
    "ref_amb": "/path/to/Homo_sapiens_assembly19.fasta.amb",
    "ref_ann": "/path/to/Homo_sapiens_assembly19.fasta.ann",
    "ref_bwt": "/path/to/Homo_sapiens_assembly19.fasta.bwt",
    "ref_name": "hg19"
  },
  "mutation_calling.dbSNP_vcf_index": "/path/to/dbsnp_138.b37.vcf.gz.tbi",
  ...
}
```

Now `refGenome` has all the values it needs for our tasks.

In addition, we have replaced all the reference genome inputs in call `BwaMem` with `refGenome` in order to pass information to a task via structs.

Within the `BwaMem` task, we must refer to variables inside the struct, such as `refGenome.ref_name` (which has a value of "hg19" using this JSON metadata):

```         
# Align fastq file to the reference genome
task BwaMem {
  input {
    File input_fastq
    referenceGenome refGenome
  }
  
  String base_file_name = basename(input_fastq, ".fastq")
  String ref_fasta_local = basename(refGenome.ref_fasta)

  String read_group_id = "ID:" + base_file_name
  String sample_name = "SM:" + base_file_name
  String platform_info = "PL:illumina"


  command <<<
    set -eo pipefail

    mv "~{refGenome.ref_fasta}" .
    mv "~{refGenome.ref_fasta_index}" .
    mv "~{refGenome.ref_dict}" .
    mv "~{refGenome.ref_amb}" .
    mv "~{refGenome.ref_ann}" .
    mv "~{refGenome.ref_bwt}" .
    mv "~{refGenome.ref_pac}" .
    mv "~{refGenome.ref_sa}" .

    bwa mem \
      -p -v 3 -t 16 -M -R '@RG\t~{read_group_id}\t~{sample_name}\t~{platform_info}' \
      "~{ref_fasta_local}" "~{input_fastq}" > "~{base_file_name}.sam"
    samtools view -1bS -@ 15 -o "~{base_file_name}.aligned.bam" "~{base_file_name}.sam"
    samtools sort -@ 15 -o "~{base_file_name}.sorted_query_aligned.bam" "~{base_file_name}.aligned.bam"
  >>>

  output {
    File analysisReadySorted = "~{base_file_name}.sorted_query_aligned.bam"
  }
  
  runtime {
    memory: "48 GB"
    cpu: 16
    docker: "ghcr.io/getwilds/bwa:0.7.17"
  }
}
```

Other tasks in the workflow, such as `ApplyBaseRecalibrator` and `Mutect2TumorOnly` also make use of the reference genome, so we pass `refGenome` to it. The final task `annovar` only requires the reference genome name, and none of the files in the `referenceGenome` struct. We make a stylistic choice to pass only `refGenome.ref_name` to the input of `annovar` task call, as the task doesn't need the full information of the struct. This stylistic choice is based on the principle of passing on the minimally needed information for a modular piece of code to run, which makes the task `annovar` depend on the minimal amount of inputs. This will also save us time and disk space by not having to localize several gigabytes of reference files into the Docker container that `annovar` will be running in.

```         
 call annovar {
    input:
      input_vcf = Mutect2TumorOnly.output_vcf,
      ref_name = refGenome.ref_name,
      annovar_operation = annovar_operation,
      annovar_protocols = annovar_protocols
  }
```

Putting everything together in the workflow:

```         
version 1.0

struct referenceGenome {
    File ref_fasta
    File ref_fasta_index
    File ref_dict
    File ref_amb
    File ref_ann
    File ref_bwt
    File ref_pac
    File ref_sa
    String ref_name
}

workflow mutation_calling {
  input {
    File sampleFastq

    referenceGenome refGenome
    
    # Files for specific tools
    File dbSNP_vcf
    File dbSNP_vcf_index
    File known_indels_sites_VCFs
    File known_indels_sites_indices
    File af_only_gnomad
    File af_only_gnomad_index

    # Annovar options
    String annovar_protocols
    String annovar_operation
  }
    
  # Map reads to reference
  call BwaMem {
    input:
      input_fastq = sampleFastq,
      refGenome = refGenome
  }
  
  call MarkDuplicates {
    input:
      input_bam = BwaMem.analysisReadySorted
  }

  call ApplyBaseRecalibrator {
    input:
      input_bam = MarkDuplicates.markDuplicates_bam,
      input_bam_index = MarkDuplicates.markDuplicates_bai,
      dbSNP_vcf = dbSNP_vcf,
      dbSNP_vcf_index = dbSNP_vcf_index,
      known_indels_sites_VCFs = known_indels_sites_VCFs,
      known_indels_sites_indices = known_indels_sites_indices,
      refGenome = refGenome
  }

  call Mutect2TumorOnly {
    input:
      input_bam = ApplyBaseRecalibrator.recalibrated_bam,
      input_bam_index = ApplyBaseRecalibrator.recalibrated_bai,
      refGenome = refGenome,
      genomeReference = af_only_gnomad,
      genomeReferenceIndex = af_only_gnomad_index
  }
  
  call annovar {
    input:
      input_vcf = Mutect2TumorOnly.output_vcf,
      ref_name = refGenome.ref_name,
      annovar_operation = annovar_operation,
      annovar_protocols = annovar_protocols
  }
  
  # Outputs that will be retained when execution is complete
  output {
    File alignedBamSorted = BwaMem.analysisReadySorted
    File markDuplicates_bam = MarkDuplicates.markDuplicates_bam
    File markDuplicates_bai = MarkDuplicates.markDuplicates_bai
    File analysisReadyBam = ApplyBaseRecalibrator.recalibrated_bam 
    File analysisReadyIndex = ApplyBaseRecalibrator.recalibrated_bai
    File Mutect_Vcf = Mutect2TumorOnly.output_vcf
    File Mutect_VcfIndex = Mutect2TumorOnly.output_vcf_index
    File Mutect_AnnotatedVcf = annovar.output_annotated_vcf
    File Mutect_AnnotatedTable = annovar.output_annotated_table
  }

  parameter_meta {
    sampleFastq: "Tumor .fastq (expects Illumina)"

    dbSNP_vcf: "dbSNP VCF for mutation calling"
    dbSNP_vcf_index: "dbSNP VCF index"
    known_indels_sites_VCFs: "Known indel site VCF for mutation calling"
    known_indels_sites_indices: "Known indel site VCF indicies"
    af_only_gnomad: "gnomAD population allele fraction for mutation calling"
    af_only_gnomad_index: "gnomAD population allele fraction index"

    annovar_protocols: "annovar protocols: see https://annovar.openbioinformatics.org/en/latest/user-guide/startup"
    annovar_operation: "annovar operation: see https://annovar.openbioinformatics.org/en/latest/user-guide/startup"
  }
}

####################
# Task definitions #
####################

# Align fastq file to the reference genome
task BwaMem {
  input {
    File input_fastq
    referenceGenome refGenome
  }
  
  String base_file_name = basename(input_fastq, ".fastq")
  String ref_fasta_local = basename(refGenome.ref_fasta)

  String read_group_id = "ID:" + base_file_name
  String sample_name = "SM:" + base_file_name
  String platform_info = "PL:illumina"


  command <<<
    set -eo pipefail

    mv "~{refGenome.ref_fasta}" .
    mv "~{refGenome.ref_fasta_index}" .
    mv "~{refGenome.ref_dict}" .
    mv "~{refGenome.ref_amb}" .
    mv "~{refGenome.ref_ann}" .
    mv "~{refGenome.ref_bwt}" .
    mv "~{refGenome.ref_pac}" .
    mv "~{refGenome.ref_sa}" .

    bwa mem \
      -p -v 3 -t 16 -M -R '@RG\t~{read_group_id}\t~{sample_name}\t~{platform_info}' \
      "~{ref_fasta_local}" "~{input_fastq}" > "~{base_file_name}.sam"
    samtools view -1bS -@ 15 -o "~{base_file_name}.aligned.bam" "~{base_file_name}.sam"
    samtools sort -n -@ 15 -o "~{base_file_name}.sorted_query_aligned.bam" "~{base_file_name}.aligned.bam"
  >>>

  output {
    File analysisReadySorted = "~{base_file_name}.sorted_query_aligned.bam"
  }
  
  runtime {
    memory: "48 GB"
    cpu: 16
    docker: "ghcr.io/getwilds/bwa:0.7.17"
  }
}

# Mark duplicates on a BAM file
task MarkDuplicates {
  input {
    File input_bam
  }

  String base_file_name = basename(input_bam, ".sorted_query_aligned.bam")

  command <<<
    gatk MarkDuplicates \
      --INPUT "~{input_bam}" \
      --OUTPUT "~{base_file_name}.duplicates_marked.bam" \
      --METRICS_FILE "~{base_file_name}.duplicate_metrics" \
      --CREATE_INDEX true \
      --OPTICAL_DUPLICATE_PIXEL_DISTANCE 100 \
      --VALIDATION_STRINGENCY SILENT
  >>>

  runtime {
    docker: "ghcr.io/getwilds/gatk:4.3.0.0"
    memory: "48 GB"
    cpu: 4
  }

  output {
    File markDuplicates_bam = "~{base_file_name}.duplicates_marked.bam"
    File markDuplicates_bai = "~{base_file_name}.duplicates_marked.bai"
    File duplicate_metrics = "~{base_file_name}.duplicates_marked.bai"
  }
}

# Base quality recalibration
task ApplyBaseRecalibrator {
  input {
    File input_bam
    File input_bam_index
    File dbSNP_vcf
    File dbSNP_vcf_index
    File known_indels_sites_VCFs
    File known_indels_sites_indices
    referenceGenome refGenome
  }
  
  String base_file_name = basename(input_bam, ".duplicates_marked.bam")
  
  String ref_fasta_local = basename(refGenome.ref_fasta)
  String dbSNP_vcf_local = basename(dbSNP_vcf)
  String known_indels_sites_VCFs_local = basename(known_indels_sites_VCFs)


  command <<<
  set -eo pipefail

  mv "~{refGenome.ref_fasta}" .
  mv "~{refGenome.ref_fasta_index}" .
  mv "~{refGenome.ref_dict}" .

  mv "~{dbSNP_vcf}" .
  mv "~{dbSNP_vcf_index}" .

  mv "~{known_indels_sites_VCFs}" .
  mv "~{known_indels_sites_indices}" .

  samtools index "~{input_bam}"

  gatk --java-options "-Xms8g" \
      BaseRecalibrator \
      -R "~{ref_fasta_local}" \
      -I "~{input_bam}" \
      -O "~{base_file_name}.recal_data.csv" \
      --known-sites "~{dbSNP_vcf_local}" \
      --known-sites "~{known_indels_sites_VCFs_local}" \
      

  gatk --java-options "-Xms8g" \
      ApplyBQSR \
      -bqsr "~{base_file_name}.recal_data.csv" \
      -I "~{input_bam}" \
      -O "~{base_file_name}.recal.bam" \
      -R "~{ref_fasta_local}" \
      

  # finds the current sort order of this bam file
  samtools view -H "~{base_file_name}.recal.bam" | grep @SQ | sed 's/@SQ\tSN:\|LN://g' > "~{base_file_name}.sortOrder.txt"
>>>

  output {
    File recalibrated_bam = "~{base_file_name}.recal.bam"
    File recalibrated_bai = "~{base_file_name}.recal.bai"
    File sortOrder = "~{base_file_name}.sortOrder.txt"
  }
  runtime {
    memory: "36 GB"
    cpu: 2
    docker: "ghcr.io/getwilds/gatk:4.3.0.0"
  }
}

# Variant calling via mutect2 (tumor-only mode)
task Mutect2TumorOnly {
  input {
    File input_bam
    File input_bam_index
    referenceGenome refGenome
    File genomeReference
    File genomeReferenceIndex
  }

    String base_file_name = basename(input_bam, ".recal.bam")
    String ref_fasta_local = basename(refGenome.ref_fasta)
    String genomeReference_local = basename(genomeReference)

command <<<
    set -eo pipefail

    mv "~{refGenome.ref_fasta}" .
    mv "~{refGenome.ref_fasta_index}" .
    mv "~{refGenome.ref_dict}" .
    mv "~{genomeReference}" .
    mv "~{genomeReferenceIndex}" .

    gatk --java-options "-Xms16g" Mutect2 \
      -R "~{ref_fasta_local}" \
      -I "~{input_bam}" \
      -O preliminary.vcf.gz \
      --germline-resource "~{genomeReference_local}" \
     
    gatk --java-options "-Xms16g" FilterMutectCalls \
      -V preliminary.vcf.gz \
      -O "~{base_file_name}.mutect2.vcf.gz" \
      -R "~{ref_fasta_local}" \
      --stats preliminary.vcf.gz.stats \
     
>>>

runtime {
    docker: "ghcr.io/getwilds/gatk:4.3.0.0"
    memory: "24 GB"
    cpu: 1
  }

output {
    File output_vcf = "~{base_file_name}.mutect2.vcf.gz"
    File output_vcf_index = "~{base_file_name}.mutect2.vcf.gz.tbi"
  }

}

# Annotate VCF using annovar
task annovar {
  input {
    File input_vcf
    String ref_name
    String annovar_protocols
    String annovar_operation
  }
  String base_vcf_name = basename(input_vcf, ".vcf.gz")
  
  command <<<
    set -eo pipefail
  
    perl /annovar/table_annovar.pl "~{input_vcf}" /annovar/humandb/ \
      -buildver "~{ref_name}" \
      -outfile "~{base_vcf_name}" \
      -remove \
      -protocol "~{annovar_protocols}" \
      -operation "~{annovar_operation}" \
      -nastring . -vcfinput
  >>>
  runtime {
    docker : "ghcr.io/getwilds/annovar:${ref_name}"
    cpu: 1
    memory: "2GB"
  }
  output {
    File output_annotated_vcf = "~{base_vcf_name}.${ref_name}_multianno.vcf"
    File output_annotated_table = "~{base_vcf_name}.${ref_name}_multianno.txt"
  }
}
```

The JSON metadata:

```
{
  "mutation_calling.sampleFastq": "/path/to/Tumor_2_EGFR_HCC4006_combined.fastq",
  "mutation_calling.refGenome": {
    "ref_fasta": "/path/to/Homo_sapiens_assembly19.fasta",
    "ref_fasta_index": "/path/to/Homo_sapiens_assembly19.fasta.fai",
    "ref_dict": "/path/to/Homo_sapiens_assembly19.dict",
    "ref_pac": "/path/to/Homo_sapiens_assembly19.fasta.pac",
    "ref_sa": "/path/to/Homo_sapiens_assembly19.fasta.sa",
    "ref_amb": "/path/to/Homo_sapiens_assembly19.fasta.amb",
    "ref_ann": "/path/to/Homo_sapiens_assembly19.fasta.ann",
    "ref_bwt": "/path/to/Homo_sapiens_assembly19.fasta.bwt",
    "ref_name": "hg19"
  },
  "mutation_calling.dbSNP_vcf_index": "/path/to/dbsnp_138.b37.vcf.gz.tbi",
  "mutation_calling.dbSNP_vcf": "/path/to/dbsnp_138.b37.vcf.gz",
  "mutation_calling.known_indels_sites_indices": "/path/to/Mills_and_1000G_gold_standard.indels.b37.sites.vcf.idx",
  "mutation_calling.known_indels_sites_VCFs": "/path/to/Mills_and_1000G_gold_standard.indels.b37.sites.vcf",
  "mutation_calling.af_only_gnomad": "/path/to/af-only-gnomad.raw.sites.b37.vcf.gz",
  "mutation_calling.af_only_gnomad_index": "/path/to/af-only-gnomad.raw.sites.b37.vcf.gz.tbi",
  "mutation_calling.annovar_protocols": "refGene,knownGene,cosmic70,esp6500siv2_all,clinvar_20180603,gnomad211_exome",
  "mutation_calling.annovar_operation": "g,f,f,f,f,f"
}
```

<details>
<summary><b>The JSON using the Fred Hutch HPC</b></summary>

```
{
  "mutation_calling.sampleFastq": "/fh/fast/paguirigan_a/pub/ReferenceDataSets/workflow_testing_data/WDL/wdl_101/HCC4006_final.fastq",
  "mutation_calling.refGenome": {
    "ref_fasta": "/fh/fast/paguirigan_a/pub/ReferenceDataSets/genome_data/human/hg19/Homo_sapiens_assembly19.fasta",
    "ref_fasta_index": "/fh/fast/paguirigan_a/pub/ReferenceDataSets/genome_data/human/hg19/Homo_sapiens_assembly19.fasta.fai",
    "ref_dict": "/fh/fast/paguirigan_a/pub/ReferenceDataSets/genome_data/human/hg19/Homo_sapiens_assembly19.dict",
    "ref_pac": "/fh/fast/paguirigan_a/pub/ReferenceDataSets/genome_data/human/hg19/Homo_sapiens_assembly19.fasta.pac",
    "ref_sa": "/fh/fast/paguirigan_a/pub/ReferenceDataSets/genome_data/human/hg19/Homo_sapiens_assembly19.fasta.sa",
    "ref_amb": "/fh/fast/paguirigan_a/pub/ReferenceDataSets/genome_data/human/hg19/Homo_sapiens_assembly19.fasta.amb",
    "ref_ann": "/fh/fast/paguirigan_a/pub/ReferenceDataSets/genome_data/human/hg19/Homo_sapiens_assembly19.fasta.ann",
    "ref_bwt": "/fh/fast/paguirigan_a/pub/ReferenceDataSets/genome_data/human/hg19/Homo_sapiens_assembly19.fasta.bwt",
    "ref_name": "hg19"
  },
  "mutation_calling.dbSNP_vcf_index": "/fh/fast/paguirigan_a/pub/ReferenceDataSets/genome_data/human/hg19/dbsnp_138.b37.vcf.gz.tbi",
  "mutation_calling.dbSNP_vcf": "/fh/fast/paguirigan_a/pub/ReferenceDataSets/genome_data/human/hg19/dbsnp_138.b37.vcf.gz",
  "mutation_calling.known_indels_sites_indices": "/fh/fast/paguirigan_a/pub/ReferenceDataSets/genome_data/human/hg19/Mills_and_1000G_gold_standard.indels.b37.sites.vcf.idx",
  "mutation_calling.known_indels_sites_VCFs": "/fh/fast/paguirigan_a/pub/ReferenceDataSets/genome_data/human/hg19/Mills_and_1000G_gold_standard.indels.b37.sites.vcf",
  "mutation_calling.af_only_gnomad": "/fh/fast/paguirigan_a/pub/ReferenceDataSets/genome_data/human/hg19/af-only-gnomad.raw.sites.b37.vcf.gz",
  "mutation_calling.af_only_gnomad_index": "/fh/fast/paguirigan_a/pub/ReferenceDataSets/genome_data/human/hg19/af-only-gnomad.raw.sites.b37.vcf.gz.tbi",
  "mutation_calling.annovar_protocols": "refGene,knownGene,cosmic70,esp6500siv2_all,clinvar_20180603,gnomad211_exome",
  "mutation_calling.annovar_operation": "g,f,f,f,f,f"
}
```

</details>
<iframe src="https://docs.google.com/forms/d/e/1FAIpQLSeEKGWTJOowBhFlWftPUjFU8Rfj-d9iXIHENyd8_HGS8PM7kw/viewform?embedded=true" width="640" height="886" frameborder="0" marginheight="0" marginwidth="0">Loading…</iframe>
