

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

<script src="https://gist.github.com/fhdsl-robot/3e3e3793482b3517b4b3fdbeb4a4c913.js"></script>

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
