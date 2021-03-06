#Expecting the following files (outputs from the previous step): 
#combined_aligned.fasta - an aligned fasta file with the two mitogenomes titled *.1 and *.2.fa for each sample as well as the reference sample. Each sequence should only span one line
#For each phased sample, a vcf file prefixed with sample name showing the quality/phase of the various genotypes (suffixed *.phased_SNPs.vcf)

postprocess <- function(working_dir) {#1A
#e.g. postprocess("/Users/alanaalexander/Dropbox/polg_mice")

library(gtools)  
  
#Getting the sample names from the vcf files in the folder
samplenames <- unique(gsub(".phased_SNPs.vcf","",list.files(working_dir, pattern=".phased_SNPs.vcf")))

#Grabbing the aligned fasta files and figuring out the total number of nucleotides in the alignment
input_fasta <- readLines(paste(working_dir,"/","combined_aligned.fasta",sep=""))
nochars <- length(strsplit(input_fasta[2],"")[[1]])

#creating an inputmatrix which will have a column for each sequence and the relative ref_pos
inputmat <- matrix(NA,nrow=(nochars+1),ncol=(length(seq(1,length(input_fasta),2))+1))
inputmat[1,1:(length(seq(1,length(input_fasta),2)))] <- input_fasta[(seq(1,length(input_fasta),2))]

#populating the rows with sequence from the fasta file  
for (i in 1:(length(seq(1,length(input_fasta),2)))) {
  inputmat[2:(dim(inputmat)[1]),i] <- strsplit(input_fasta[i*2],"")[[1]]
}

#finding out what the reference column is (not present in the vcf sample names)
ref_column <- which(!(gsub("\\..*","",gsub(">","",inputmat[1,]))[1:(length(seq(1,length(input_fasta),2)))] %in% samplenames))

#creating a column giving the position relative to the reference sequence  
inputmat[1,((length(seq(1,length(input_fasta),2)))+1)] <- "ref_pos"

#populating this column - giving indel positions "compound" sites e.g. 484, 484_1, 484_2 so they are still relative to the reference  
ref_site <- 1
for (i in 2:(dim(inputmat)[1])) {
  if(!(inputmat[i,ref_column]=="-")) {
    inputmat[i,((length(seq(1,length(input_fasta),2)))+1)] <- ref_site
    ref_site <- ref_site + 1
    site_suffix <- 1
  } else {
    inputmat[i,((length(seq(1,length(input_fasta),2)))+1)] <- paste((ref_site-1),"_",site_suffix,sep="")
    site_suffix <- site_suffix + 1    
  }
}

#Getting the output matrix ready. This is going to have the ref_pos in the first column, ref base in the next
outputmat <- inputmat[,c(((length(seq(1,length(input_fasta),2)))+1),ref_column)]

sampcount <- 1  
#pulling in the vcf to work out if sites can be confidently phased or not  
for (i in samplenames) { #2A
  print(paste("Up to sample",i,"(",sampcount,"out of a total of",length(samplenames),")"))
  sampcount <- sampcount + 1
  flush.console()
  #Getting a matrix together for the VCF file per sample
  VCF_name <- paste(i,".phased_SNPs.vcf",sep="")
  tempVCF <- readLines(paste(working_dir,"/",VCF_name,sep=""))
  tempVCF <- tempVCF[grep("^\\#",tempVCF,invert=TRUE)]
  VCFmat <- matrix(NA,ncol=5,nrow=length(gsub("\\..*GT","",gsub("^.*?\t","",tempVCF))))
  VCFmat[,1] <- unlist(strsplit(tempVCF,"\t"))[seq(2,length(unlist(strsplit(tempVCF,"\t"))),10)]
  VCFmat[,2] <- unlist(strsplit(tempVCF,"\t"))[seq(4,length(unlist(strsplit(tempVCF,"\t"))),10)]
  VCFmat[,3] <- unlist(strsplit(tempVCF,"\t"))[seq(5,length(unlist(strsplit(tempVCF,"\t"))),10)]
  VCFmat[,4] <- unlist(strsplit(tempVCF,"\t"))[seq(9,length(unlist(strsplit(tempVCF,"\t"))),10)]
  VCFmat[,5] <- unlist(strsplit(tempVCF,"\t"))[seq(10,length(unlist(strsplit(tempVCF,"\t"))),10)]
  
  #Pulling out the sequence for the sample we are interested in, so we can get the phasing blocks defined
  samplecols <- c(which(inputmat[1,] %in% paste(">",i,".1",sep="")),which(inputmat[1,] %in% paste(">",i,".2",sep="")))
  tempsamplematrix <- matrix(NA,ncol=7,nrow=dim(inputmat)[1])
  tempsamplematrix[,1] <- outputmat[,1]
  tempsamplematrix[,3:4] <- inputmat[,samplecols]
  tempsamplematrix[1,5] <- paste(i,"_phasing",sep="")
  tempsamplematrix[1,6] <- paste(i,"_hap1.fa",sep="")
  tempsamplematrix[1,7] <- paste(i,"_hap2.fa",sep="")
  
  #Identifying the sites where there is more than one allele
  for (j in 2:dim(inputmat)[1]) {
    if(!(tempsamplematrix[j,3]==tempsamplematrix[j,4])) {
      tempsamplematrix[j,5] <- "Unknown"
    }
  }
  #Propogating the sequence over for sites that do not show signs of alternate alleles
  tempsamplematrix[(which(is.na(tempsamplematrix[,5]))),6] <- tempsamplematrix[(which(is.na(tempsamplematrix[,5]))),3]
  tempsamplematrix[(which(is.na(tempsamplematrix[,5]))),7] <- tempsamplematrix[(which(is.na(tempsamplematrix[,5]))),3]
  
  #Removing the rows which have indels to other samples (we'll add these back in at the end)
  indel_rows <- tempsamplematrix[(which(tempsamplematrix[,6]=="-")),]
  tempsamplematrix <- tempsamplematrix[-(which(tempsamplematrix[,6]=="-")),]
  
  #Getting the reference relative to the sample.2.fa, because this is what the VCF is relative to
  tempsamplematrix[1,2] <- "ref_sample"
  ref_site <- 1
  for (j in 2:(dim(tempsamplematrix)[1])) {
    if(!(tempsamplematrix[j,4]=="-")) {
      tempsamplematrix[j,2] <- ref_site
      ref_site <- ref_site + 1
      site_suffix <- 1
    } else {
      tempsamplematrix[j,2]  <- paste((ref_site-1),"_",site_suffix,sep="")
      site_suffix <- site_suffix + 1    
    }
  }
  
  #Haplotype logging
  hapmat <- NULL
  
  #Looping through the VCF file and propogating those bases to the output seq if the genotype is certain
  for (j in 1:dim(VCFmat)[1]) {#3A For each site in the VCF matrix
    if(nchar(VCFmat[j,4])==nchar(gsub("PQ","",VCFmat[j,4]))) {#4A If it is NOT a quality genotype (PQ is NOT present)
       if(nchar(VCFmat[j,2])==nchar(VCFmat[j,3])) {#5A If it isn't an indel (the number of characters equals each other)
       #Then just copy the original reads to the last columns. Prefix the "Unknown" reads with the read depth for each allele
       tempsamplematrix[(which(tempsamplematrix[,2]==VCFmat[j,1])),6] <- VCFmat[j,2]
       tempsamplematrix[(which(tempsamplematrix[,2]==VCFmat[j,1])),7] <- VCFmat[j,3]
       tempsamplematrix[(which(tempsamplematrix[,2]==VCFmat[j,1])),5] <- paste("Unknown_",gsub(",",":",unlist(strsplit(VCFmat[j,5],":"))[2]),sep="")
       } else { #5AB
         # what to do when no PQ and it is an indel
         siterows <- max(nchar(VCFmat[j,2:3]))
         #Pad our calls out with "-" if necessary
         if(nchar(VCFmat[j,2])<siterows) {
            VCFmat[j,2] <- paste(VCFmat[j,2],paste(rep("-",(siterows-nchar(VCFmat[j,2]))),collapse=""),sep="")
         }
         if(nchar(VCFmat[j,3])<siterows) {
           VCFmat[j,3] <- paste(VCFmat[j,3],paste(rep("-",(siterows-nchar(VCFmat[j,3]))),collapse=""),sep="")
         }
         read_depth <- unlist(strsplit(unlist(strsplit(VCFmat[j,5],":"))[2],","))
         # For each of the sites involved in the indel, paste this in to rows 6 and 7
         for(k in 0:(siterows-1)) {
           tempsamplematrix[((which(tempsamplematrix[,2]==VCFmat[j,1]))+k),6] <- unlist(strsplit(VCFmat[j,2],""))[k+1]
           tempsamplematrix[((which(tempsamplematrix[,2]==VCFmat[j,1]))+k),7] <- unlist(strsplit(VCFmat[j,3],""))[k+1]
           tempsamplematrix[((which(tempsamplematrix[,2]==VCFmat[j,1]))+k),5] <- paste("Unknown_",gsub(",",":",unlist(strsplit(VCFmat[j,5],":"))[2]),sep="")
         }
       }  #5B
    } else { #4AB  If it IS a quality genotype (PQ is present)
       if(nchar(VCFmat[j,2])==nchar(VCFmat[j,3])) {#5A If it doesn't involve an indel
          haps <- unlist(strsplit(unlist(strsplit(VCFmat[j,5],":"))[5],",")) # Get the two haplotypes from VCFmat[,5]
          if(is.null(hapmat)) {# 6A If we haven't discovered any haplotypes yet
            #Then make the haplotype for this site the first entry in our hapmat
            hapmat <- t(as.matrix(haps))
            #Then just copy the original reads to the last columns. Combine haplotype name with the read depth for each allele
            tempsamplematrix[(which(tempsamplematrix[,2]==VCFmat[j,1])),6] <- VCFmat[j,2]
            tempsamplematrix[(which(tempsamplematrix[,2]==VCFmat[j,1])),7] <- VCFmat[j,3]
            read_depth <- unlist(strsplit(unlist(strsplit(VCFmat[j,5],":"))[2],","))
            tempsamplematrix[(which(tempsamplematrix[,2]==VCFmat[j,1])),5] <- paste(haps[1],"_",read_depth[1],":",haps[2],"_",read_depth[2],sep="")
          } else { #6AB If we have previosly logged haplotypes
            if(haps[1] %in% hapmat) { #7A If this haplotype is one that we have previously logged
              if(haps[1] %in% hapmat[,1]) { #8A If the alleles are the same way around in this site as previous
                #Then just copy the original reads to the last columns. Combine haplotype name with the read depth for each allele
                tempsamplematrix[(which(tempsamplematrix[,2]==VCFmat[j,1])),6] <- VCFmat[j,2]
                tempsamplematrix[(which(tempsamplematrix[,2]==VCFmat[j,1])),7] <- VCFmat[j,3]
                read_depth <- unlist(strsplit(unlist(strsplit(VCFmat[j,5],":"))[2],","))
                tempsamplematrix[(which(tempsamplematrix[,2]==VCFmat[j,1])),5] <- paste(haps[1],"_",read_depth[1],":",haps[2],"_",read_depth[2],sep="")
              } else { #8AB If the alleles are the other way around
                #Then invert the order when copying to the last columns. Combine (inverted) haplotype name with the read depth for each allele
                tempsamplematrix[(which(tempsamplematrix[,2]==VCFmat[j,1])),6] <- VCFmat[j,3]
                tempsamplematrix[(which(tempsamplematrix[,2]==VCFmat[j,1])),7] <- VCFmat[j,2]
                read_depth <- unlist(strsplit(unlist(strsplit(VCFmat[j,5],":"))[2],","))
                tempsamplematrix[(which(tempsamplematrix[,2]==VCFmat[j,1])),5] <- paste(haps[2],"_",read_depth[2],":",haps[1],"_",read_depth[1],sep="")
              } #8B               
            } else { #7AB If the haplotype is one we HAVEN'T previously logged
              #Add the haplotype to our hapmat
              hapmat <- rbind(hapmat,haps)
              #Then just copy the original reads to the last columns. Combine haplotype name with the read depth for each allele
              tempsamplematrix[(which(tempsamplematrix[,2]==VCFmat[j,1])),6] <- VCFmat[j,2]
              tempsamplematrix[(which(tempsamplematrix[,2]==VCFmat[j,1])),7] <- VCFmat[j,3]
              read_depth <- unlist(strsplit(unlist(strsplit(VCFmat[j,5],":"))[2],","))
              tempsamplematrix[(which(tempsamplematrix[,2]==VCFmat[j,1])),5] <- paste(haps[1],"_",read_depth[1],":",haps[2],"_",read_depth[2],sep="")
            } #7B
         } #6B   
       } else { #5AB If it does involve an indel
          haps <- unlist(strsplit(unlist(strsplit(VCFmat[j,5],":"))[5],","))
          if(is.null(hapmat)) { # 6A If we haven't discovered any haplotypes yet
            #Then make the haplotype for this site the first entry in our hapmat
            hapmat <- t(as.matrix(haps))
            #Find the number of sites our indel covers
            siterows <- max(nchar(VCFmat[j,2:3]))
            #Pad our calls out with "-" if necessary
            if(nchar(VCFmat[j,2])<siterows) {
               VCFmat[j,2] <- paste(VCFmat[j,2],paste(rep("-",(siterows-nchar(VCFmat[j,2]))),collapse=""),sep="")
            }
            if(nchar(VCFmat[j,3])<siterows) {
              VCFmat[j,3] <- paste(VCFmat[j,3],paste(rep("-",(siterows-nchar(VCFmat[j,3]))),collapse=""),sep="")
            }
            read_depth <- unlist(strsplit(unlist(strsplit(VCFmat[j,5],":"))[2],","))
            # For each of the sites involved in the indel, paste this in to rows 6 and 7
            for(k in 0:(siterows-1)) {
              tempsamplematrix[((which(tempsamplematrix[,2]==VCFmat[j,1]))+k),6] <- unlist(strsplit(VCFmat[j,2],""))[k+1]
              tempsamplematrix[((which(tempsamplematrix[,2]==VCFmat[j,1]))+k),7] <- unlist(strsplit(VCFmat[j,3],""))[k+1]
              tempsamplematrix[((which(tempsamplematrix[,2]==VCFmat[j,1]))+k),5] <- paste(haps[1],"_",read_depth[1],":",haps[2],"_",read_depth[2],sep="")
            }
          } else {  #6AB Or if we have discovered haplotypes
            if(haps[1] %in% hapmat) { #7A and particularly if we have discovered this specific haplotype
              if(haps[1] %in% hapmat[,1]) {# 8A and the VCF is in the same order as our previous haplotype
                #Then do the same steps as when no previous haplotypes had been discovered
                siterows <- max(nchar(VCFmat[j,2:3]))
                if(nchar(VCFmat[j,2])<siterows) {
                  VCFmat[j,2] <- paste(VCFmat[j,2],paste(rep("-",(siterows-nchar(VCFmat[j,2]))),collapse=""),sep="")
                }
                if(nchar(VCFmat[j,3])<siterows) {
                  VCFmat[j,3] <- paste(VCFmat[j,3],paste(rep("-",(siterows-nchar(VCFmat[j,3]))),collapse=""),sep="")
                }
                read_depth <- unlist(strsplit(unlist(strsplit(VCFmat[j,5],":"))[2],","))
                for(k in 0:(siterows-1)) {
                  tempsamplematrix[((which(tempsamplematrix[,2]==VCFmat[j,1]))+k),6] <- unlist(strsplit(VCFmat[j,2],""))[k+1]
                  tempsamplematrix[((which(tempsamplematrix[,2]==VCFmat[j,1]))+k),7] <- unlist(strsplit(VCFmat[j,3],""))[k+1]
                  tempsamplematrix[((which(tempsamplematrix[,2]==VCFmat[j,1]))+k),5] <- paste(haps[1],"_",read_depth[1],":",haps[2],"_",read_depth[2],sep="")
                }                
              } else {  #8AB OR if the VCFmat has the haplotypes in the opposite order then do the same thing but invert the calls
                siterows <- max(nchar(VCFmat[j,2:3]))
                if(nchar(VCFmat[j,2])<siterows) {
                  VCFmat[j,2] <- paste(VCFmat[j,2],paste(rep("-",(siterows-nchar(VCFmat[j,2]))),collapse=""),sep="")
                }
                if(nchar(VCFmat[j,3])<siterows) {
                  VCFmat[j,3] <- paste(VCFmat[j,3],paste(rep("-",(siterows-nchar(VCFmat[j,3]))),collapse=""),sep="")
                }
                read_depth <- unlist(strsplit(unlist(strsplit(VCFmat[j,5],":"))[2],","))
                for(k in 0:(siterows-1)) {
                  tempsamplematrix[((which(tempsamplematrix[,2]==VCFmat[j,1]))+k),6] <- unlist(strsplit(VCFmat[j,3],""))[k+1]
                  tempsamplematrix[((which(tempsamplematrix[,2]==VCFmat[j,1]))+k),7] <- unlist(strsplit(VCFmat[j,2],""))[k+1]
                  tempsamplematrix[((which(tempsamplematrix[,2]==VCFmat[j,1]))+k),5] <- paste(haps[2],"_",read_depth[2],":",haps[1],"_",read_depth[1],sep="")
                }
              }#8B
           } else { #7AB OR, if we haven't previously discovered this haplotype   
              #Add this haplotype to the pile, and then do the same steps as previous
              hapmat <- rbind(hapmat,haps)
              siterows <- max(nchar(VCFmat[j,2:3]))
              if(nchar(VCFmat[j,2])<siterows) {
                  VCFmat[j,2] <- paste(VCFmat[j,2],paste(rep("-",(siterows-nchar(VCFmat[j,2]))),collapse=""),sep="")
              }
              if(nchar(VCFmat[j,3])<siterows) {
                  VCFmat[j,3] <- paste(VCFmat[j,3],paste(rep("-",(siterows-nchar(VCFmat[j,3]))),collapse=""),sep="")
              }
              read_depth <- unlist(strsplit(unlist(strsplit(VCFmat[j,5],":"))[2],","))
              for(k in 0:(siterows-1)) {
                tempsamplematrix[((which(tempsamplematrix[,2]==VCFmat[j,1]))+k),6] <- unlist(strsplit(VCFmat[j,2],""))[k+1]
                tempsamplematrix[((which(tempsamplematrix[,2]==VCFmat[j,1]))+k),7] <- unlist(strsplit(VCFmat[j,3],""))[k+1]
                tempsamplematrix[((which(tempsamplematrix[,2]==VCFmat[j,1]))+k),5] <- paste(haps[1],"_",read_depth[1],":",haps[2],"_",read_depth[2],sep="")
              }
           }#7B
         }#6B   
       }#5B
    }#4B  
  }#3B
  #Adding alignment indel rows back in if these are present
  if(length(indel_rows)>0) {
    tempsamplematrix <- rbind(tempsamplematrix,indel_rows)
    header_row <- t(as.matrix(tempsamplematrix[1,]))
    tempsamplematrix <- tempsamplematrix[-1,]
    tempsamplematrix <- tempsamplematrix[mixedorder(tempsamplematrix[,1]),]
    tempsamplematrix <- rbind(header_row,tempsamplematrix)
  }
  
  #Populating the "uncertainty" of phasing column
  for (j in 2:(dim(tempsamplematrix)[1])) { #3A For each row
    if(!(is.na(tempsamplematrix[j,5]))) { #4A ignoring NA rows
      if(nchar(tempsamplematrix[j,5])>nchar(gsub("Unknown","",tempsamplematrix[j,5]))) { #7A Finding the rows which are uncertain
        nacheck <- 0
        counter <- 1
        while(nacheck==0) { #5A while we are still encountering NAs going "up the table"
          if((j-counter)>=1) { #>1A
            if (is.na(tempsamplematrix[(j-counter),5])) { #6A If it is an NA, populating it with the uncertain call
              tempsamplematrix[(j-counter),5] <- tempsamplematrix[j,5]
              counter <- counter + 1
            } else { #6AB If it is an NA, triggering the nacheck
              nacheck <- 1
            } #6B
          } else { #>1AB
            nacheck <- 1
          }  #>1B 
       } #5B
       nacheck <- 0
       counter <- 1
       while(nacheck==0) { #5A while we are still encountering NAs going "down the table"
         if((j+counter)<=(dim(tempsamplematrix)[1])) { #>1A
            if (is.na(tempsamplematrix[(j+counter),5])) { #6A If it is an NA, populating it with the uncertain call
              tempsamplematrix[(j+counter),5] <- tempsamplematrix[j,5]
              counter <- counter + 1
            } else { #6AB If it is an NA, triggering the nacheck
              nacheck <- 1
            } #6B
          } else { #>1AB
            nacheck <- 1
          }  #>1B           
       } #5B 
     }#4B   
   }#7B
 }#3B 
 #Doing this for the end of the mitogenome too (because of artificial linearization)
 if(!(is.na(tempsamplematrix[2,5]))) { #3A
   if(nchar(tempsamplematrix[2,5])>nchar(gsub("Unknown","",tempsamplematrix[2,5]))) { #4A
     if(is.na(tempsamplematrix[dim(tempsamplematrix)[1],5])) { #7A
       tempsamplematrix[dim(tempsamplematrix)[1],5] <- tempsamplematrix[2,5]
       nacheck <- 0
       counter <- 1
       while(nacheck==0) { #5A while we are still encountering NAs going "up the table"
          if (is.na(tempsamplematrix[(dim(tempsamplematrix)[1]-counter),5])) { #6A If it is an NA, populating it with the uncertain call
             tempsamplematrix[(dim(tempsamplematrix)[1]-counter),5] <- tempsamplematrix[2,5]
             counter <- counter + 1
          } else { #6AB If it is an NA, triggering the nacheck
          nacheck <- 1
          } #6B
       } #5B 
    } #7B 
  } #4B
} #3B 

for (j in 2:(dim(tempsamplematrix)[1])) { #3A For each row
  if(is.na(tempsamplematrix[j,5])) { #4A  NA rows
    k <- 1
    while(is.na(tempsamplematrix[(j+k),5])) {
      k <- k+1
    }
    if(unlist(strsplit(tempsamplematrix[(j+k),5],"_"))[1]==unlist(strsplit(tempsamplematrix[(j-1),5],"_"))[1]) {
      tempsamplematrix[j:(j+k-1),5] <- tempsamplematrix[(j-1),5]
    } else {
      tempsamplematrix[j:(j+k-1),5] <- "Unknown"
    }
  }
}  
outputmat <- cbind(outputmat,tempsamplematrix[,5:7])
}#2B  

write.table(outputmat,"phased_mito_haps.txt",quote=FALSE,row.names=FALSE,col.names=FALSE)

} #1B
