reformatting_sperm_csv_files <- function(working_dir,subfolder,Band,VCL,Is.valid,VSL,VAP) {
  #e.g. reformatting_sperm_csv_files("/Users/alanaalexander/Dropbox/polg_mice/Polg_sperm","mtDNA","Sample","VCL","Is.valid","VSL","VAP")
  setwd(working_dir)
  files <- list.files("./","*.csv")
  dir.create(paste(working_dir,"/sperm_analysis_working_dir/",sep=""))
  for (i in files) {
    temp <- read.csv(i, stringsAsFactors = FALSE)
    which.subfolder <- which(names(temp)==subfolder)
    which.Band <- which(names(temp)==Band)
    which.VCL <- which(names(temp)==VCL)
    which.Is.valid <- which(names(temp)==Is.valid)
    which.VSL <- which(names(temp)==VSL)
    which.VAP <- which(names(temp)==VAP)
    temp2 <- cbind(temp[,c(which.subfolder,which.Band,which.VCL,which.Is.valid,which.VSL,which.VAP)],temp[,-(c(which.subfolder,which.Band,which.VCL,which.Is.valid,which.VSL,which.VAP))])
    names(temp2)[2:6] <- c("Band","VCL","Is.valid","VSL","VAP")
    unique_folders <- unique(temp2[,1])
    for (j in unique_folders) {
      tempsubset <- temp2[which(temp2[,1]==j),2:6]
      suppressWarnings(dir.create(paste(working_dir,"/sperm_analysis_working_dir/",j,sep="")))
      write.csv(tempsubset,paste(working_dir,"/sperm_analysis_working_dir/",j,"/",i,sep=""),quote=FALSE,row.names=FALSE)
    }
  }
}
