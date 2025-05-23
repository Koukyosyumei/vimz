pragma circom 2.2.0;

include "../node_modules/circomlib/circuits/multiplexer.circom";
include "../node_modules/circomlib/circuits/mux1.circom";
include "../node_modules/circomlib/circuits/comparators.circom";
include "utils/hashers.circom";
include "utils/pixels.circom";
include "utils/state.circom";

template ResizeHash(widthOrig, widthResized, rowCountOrig, rowCountResized){
    input  IVCState() step_in;
    output IVCState() step_out;

    // private inputs
    signal input row_orig [rowCountOrig][widthOrig];
    signal input row_tran [rowCountResized][widthResized];

    // decoding signals
    signal prev_orig_hash <== step_in.orig_hash;
    signal prev_resized_hash <== step_in.tran_hash;
    
    // encoding signals
    signal next_orig_hash;
    signal next_resized_hash;

    component row_hasher_orig[rowCountOrig];
    component hasher_orig [rowCountOrig];
    for (var i = 0; i < rowCountOrig; i++) {
        row_hasher_orig[i] = ArrayHasher(widthOrig);
        hasher_orig[i] = PairHasher();
    }

    component row_hasher_resized[rowCountResized];
    component hasher_resized [rowCountResized];
    for (var i = 0; i < rowCountResized; i++) {
        row_hasher_resized[i] = ArrayHasher(widthResized);
        hasher_resized[i] = PairHasher();
    } 

    var decompressedwidthOrig = widthOrig * 10;
    var decompressedwidthResized = widthResized * 10;
    signal decompressed_row_orig [rowCountOrig][decompressedwidthOrig][3];
    signal decompressed_row_tran [rowCountResized][decompressedwidthResized][3];

    for (var i = 0; i < rowCountOrig; i++) {
        row_hasher_orig[i].array <== row_orig[i];
        hasher_orig[i].a <== i == 0 ? prev_orig_hash : hasher_orig[i-1].hash;
        hasher_orig[i].b <== row_hasher_orig[i].hash;
    }
    next_orig_hash <== hasher_orig[rowCountOrig-1].hash;

    // ----------------------------
    // calc resized hash
    // ----------------------------
    component decompressor_orig[rowCountOrig][widthOrig];
    for (var k = 0; k < rowCountOrig; k++) {
        for (var i = 0; i < widthOrig; i++) {
            decompressor_orig[k][i] = Decompressor();
            decompressor_orig[k][i].in <== row_orig[k][i];
            for (var j = 0; j < 10; j++) {
                decompressed_row_orig[k][i*10+j] <== decompressor_orig[k][i].out[j];
            }
        }
    }
    component decompressor_resized[rowCountResized][widthResized];
    for (var k = 0; k < rowCountResized; k++) {
        for (var i = 0; i < widthResized; i++) {
            decompressor_resized[k][i] = Decompressor();
            decompressor_resized[k][i].in <== row_tran[k][i];
            for (var j = 0; j < 10; j++) {
                decompressed_row_tran[k][i*10+j] <== decompressor_resized[k][i].out[j];
            }
        }
    }
    
    component lte[rowCountResized][decompressedwidthResized][3][2];

    for (var rgb = 0; rgb < 3; rgb++) {
        for (var i = 0; i < rowCountResized; i++) {
            for (var j = 0; j < decompressedwidthResized; j++) {
                var weight = i % 2 == 0 ? 2 : 1;
                var summ = (decompressed_row_orig[i][j*2][rgb]
                        + decompressed_row_orig[i][j*2+1][rgb]) * weight
                        + (decompressed_row_orig[i+1][j*2][rgb]
                        + decompressed_row_orig[i+1][j*2+1][rgb]) * (3 - weight);
                // log("---------------------------------------");
                // log(summ, decompressed_row_tran[i][j][rgb] * 6);
                // log("---------------------------------------");

                lte[i][j][rgb][0] = LessEqThan(12);
                lte[i][j][rgb][1] = LessEqThan(12);

                lte[i][j][rgb][0].in[1] <== 6;
                lte[i][j][rgb][0].in[0] <== summ - (6 * decompressed_row_tran[i][j][rgb]);
                lte[i][j][rgb][0].out === 1;

                lte[i][j][rgb][1].in[1] <== 6;
                lte[i][j][rgb][1].in[0] <== (6 * decompressed_row_tran[i][j][rgb]) - summ;
                lte[i][j][rgb][1].out === 1; 
            }		
        }
    }

    for (var i=0; i<rowCountResized; i++) {
        row_hasher_resized[i].array <== row_tran[i];
        hasher_resized[i].a <== i == 0 ? prev_resized_hash : hasher_resized[i-1].hash;
        hasher_resized[i].b <== row_hasher_resized[i].hash;
    }
    next_resized_hash <== hasher_resized[rowCountResized-1].hash;

    step_out.orig_hash <== next_orig_hash;
    step_out.tran_hash <== next_resized_hash;
}

template MultiplexerCrop(origSize, cropSize) {
    signal input inp[origSize];
    signal input sel;
    signal output out[cropSize];

    component dec = Decoder(origSize);
    component ep[cropSize];
	var selector[cropSize][origSize];

    for (var h=0; h<cropSize; h++) {
        ep[h] = EscalarProduct(origSize);
    }

    sel ==> dec.inp;

    for (var h=0; h<cropSize; h++) {
		for (var k=0; k<h; k++) {
			selector[h][k] = 0;
		}
		for (var k=0; k<origSize - h; k++) {
        	selector[h][k+h] = dec.out[k];
		}
    }

	for (var h=0; h<cropSize; h++) {
        for (var k=0; k<origSize; k++) {
            inp[k] ==> ep[h].in1[k];
            selector[h][k] ==> ep[h].in2[k];
        }
        ep[h].out ==> out[h];
	}
	dec.success === 1;
}
