#  psimgcombine.pl
#  
#  Usage:
#    psimgcombine.pl rowLength outputFileName inputImage [inputImage...]
#    
#    rowLength       The number of images to place on one row.
#    outputFileName  The name of the image file to be created.
#    inputImage      An image to output in the final image.
#  
#  Copyright 2024 CHRISTOPHER WEBBER
#  
#  Redistribution and use in source and binary forms, with or without 
#  modification, are permitted provided that the following conditions are met:
#  
#  1. Redistributions of source code must retain the above copyright notice, 
#     this list of conditions and the following disclaimer.
#  
#  2. Redistributions in binary form must reproduce the above copyright notice, 
#     this list of conditions and the following disclaimer in the documentation 
#     and/or other materials provided with the distribution.
#  
#  3. Neither the name of the copyright holder nor the names of its contributors
#     may be used to endorse or promote products derived from this software 
#     without specific prior written permission.
#  
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS “AS IS” 
#  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
#  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
#  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE 
#  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
#  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
#  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
#  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
#  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
#  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
#  POSSIBILITY OF SUCH DAMAGE.


use strict;
use warnings;

use File::Spec;
use GD;

print "\n";

my $outputFormat = "png";

if (!validateArgs(@ARGV))
{
    showHelp();
    exit -1;
}

my $rowLength = shift @ARGV;
my $imgOutputPath = shift @ARGV;
my @imgPaths = @ARGV;

my $metadataRef = calculateMetadata($rowLength, @imgPaths) or die;

my $combinedImg = createCombinedImage($rowLength, $metadataRef, @imgPaths) or die;

my ($volume, $directories, $imgOutputName) = File::Spec->splitpath($imgOutputPath);

$metadataRef->{"name"} = $imgOutputName;

writeImage($combinedImg, $outputFormat, $imgOutputPath) or die;

my $metadataOutputPath = getMetadataOutputPath($imgOutputPath);
        
writeMetadata($metadataRef, $metadataOutputPath);


sub writeMetadata
{
    my ($metadataRef, $metadataOutPath) = @_;
    my (%metadata) = %$metadataRef;
    
    my $success = open my $fh, ">", $metadataOutPath;
    if (!$success)
    {
        print("ERROR: Unable to write file to $metadataOutPath\n");
        return -1;
    }
    
    print("Writing metadata file to $metadataOutPath\n");
    
    print $fh "name: " . $metadata{"name"} . "\n";
    print $fh "width: " . $metadata{"width"} . "\n";
    print $fh "height: " . $metadata{"height"} . "\n";
    print $fh "\n";
    print $fh "images\n";
    
    foreach my $bnd (@{$metadata{"imageBounds"}})
    {
        my $line = join("\t",
            "name: " . $bnd->{"name"},
            "x: " . $bnd->{"x"},
            "y: " . $bnd->{"y"},
            "width: " . $bnd->{"width"},
            "height: " . $bnd->{"height"});
            
        $line .= "\n";
        
        print $fh $line;
    }
    
    close $fh;
}

sub getMetadataOutputPath
{
    my ($imgOutputPath) = @_;
    
    my ($volume, $directories, $file) = File::Spec->splitpath($imgOutputPath);
    
    my @nameParts = split /\./, $file;
    pop @nameParts;
    my $outputName = join("\.", @nameParts) . "-metadata.txt";
    
    my $outputFilePath = File::Spec->catpath($volume, $directories, $outputName);
    
    return $outputFilePath;
}

sub writeImage
{
    my ($gdImg, $outputFormat, $outputFilePath) = @_;
    
    #TODO: add other output types.
    if ($outputFormat ne "png")
    {
        print("ERROR: Unsupported output type. Output image format must be png.\n");
        return -1;
    }
    
    my $success = open my $fh, ">", $outputFilePath;
    if (!$success)
    {
        print("ERROR: Unable to write file to " . $outputFilePath . "\n");
        return -1;
    }
    
    binmode($fh);
    
    print("Writing image file to $outputFilePath\n");
    
    my $binData = $gdImg->png();
    print $fh $binData;
    
    close $fh;
}

sub createCombinedImage
{
    my ($rowLength, $metadataRef, @imgPaths) = @_;
    
    my %metadata = %$metadataRef;
    
    #TODO: detect if should be true color or not. defaulting to true now.
    $combinedImg = GD::Image->new($metadata{"width"}, $metadata{"height"}, 1);
    if (!defined($combinedImg))
    {
        print "Unable to create new image.";
        return undef;
    }
    
    my @imageBounds;
    my $rowImgCount = 0;
    my $rowMaxHeight = 0;
    my $currX = 0;
    my $currY = 0;
    for my $imgPath (@imgPaths)
    {
        my (undef, undef, $imgFileName) = File::Spec->splitpath($imgPath);
        
        my $img = GD::Image->new($imgPath);
        if (defined($img))
        {
            $combinedImg->copy($img, $currX, $currY, 0, 0, $img->width, $img->height);
                
            push(@imageBounds, {
                name => $imgFileName,
                x => $currX,
                y => $currY,
                width => $img->width,
                height => $img->height
            });
            
            $currX += $img->width;
                
            my $imgHeight = $img->height;
            if ($rowMaxHeight < $imgHeight)
            {
                $rowMaxHeight = $imgHeight;
            }
            
            ++$rowImgCount;
            if ($rowImgCount == $rowLength)
            {
                $currX = 0;
                $currY += $rowMaxHeight;
                
                $rowImgCount = 0;
                $rowMaxHeight = 0;
            }
        }
        else
        {
            print("Could not read image " . $imgPath);
            return undef;
        }
    }
        
    $metadataRef->{"imageBounds"} = \@imageBounds;
    
    return $combinedImg;
}

sub calculateMetadata
{
    my ($rowLength, @imgPaths) = @_;
    
    my $totalHeight = 0;
    my $rowWidth = 0;
    my $maxRowWidth = 0;
    my $rowMaxHeight = 0;
    my $rowImgCount = 0;
    
    foreach my $imgPath (@imgPaths)
    {
        my $img = GD::Image->new($imgPath);
        if (defined($img))
        {
            my $imgWidth = $img->width;
            my $imgHeight = $img->height;
            
            if ($rowMaxHeight < $imgHeight)
            {
                $rowMaxHeight = $imgHeight;
            }
            
            $rowWidth += $imgWidth;
                
            if ($rowImgCount == $rowLength - 1)
            {
                $totalHeight += $rowMaxHeight;
                
                if ($maxRowWidth < $rowWidth)
                {
                    $maxRowWidth = $rowWidth;
                }
                
                $rowImgCount = 0;
                $rowMaxHeight = 0;
                $rowWidth = 0;
            }
            else
            {
                ++$rowImgCount;
            }
        }
        else
        {
            print("Could not read image " . $imgPath);
            return undef;
        }
    }
        
    if ($rowImgCount != 0)
    {
        $totalHeight += $rowMaxHeight;
        
        if ($maxRowWidth < $rowWidth)
        {
            $maxRowWidth = $rowWidth;
        }
    }
        
    my %metadata = (
        height => $totalHeight,
        width => $maxRowWidth
    );  

    return \%metadata;
}

sub validateArgs
{
    my $ret = 1;

    if (scalar(@_) < 3)
    {
        print("ERROR: Missing arguments.\n");
        $ret = 0;
    }
    else
    {
        my $rowLength = shift @_;
        if ($rowLength !~ /\b\d+\b/ or $rowLength <= 0)
        {
            print("ERROR: Row length must be a number greater than 0.\n");
            $ret = 0;
        }
    }
    
    return $ret;
}

sub showHelp
{
    print("Usage:\n");
    print("\tpsimgcombine.pl rowLength outputFileName inputImage [inputImage...]\n\n");
    print("\trowLength:\tThe number of images to place on one row.\n");
    print("\toutputFileName:\tThe name of the image file to be created.\n");
    print("\tinputImage:\tAn image to include in the output image.\n\n");
}