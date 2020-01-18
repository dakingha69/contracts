/**
CREDITS:
// For the Elliptic Curve Pairing operations and functions verify() and verifyCalculation():
// This file is MIT Licensed.
//
// Copyright 2017 Christian Reitwiessner
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
// More information at https://gist.github.com/chriseth/f9be9d9391efc5beb9704255a8e2989d
Minor edits for Nightfall by:
Michael Connor
Duncan Westland
Chaitanya Konda
Harry R
*/

/**
@title Verifier
@dev Example Verifier Implementation - GM17 proof verification.
@notice Do not use this example in any production code!
*/

pragma solidity ^0.5.8;

// import "./Ownable.sol";
import "./Pairing.sol";

// TODO: Make library, using contract inheritance because trustlines-contract-deploy-tools not able to link libraries
contract Verifier is Pairing {

  struct Proof_GM17 {
      G1Point A;
      G2Point B;
      G1Point C;
  }

  struct Verification_Key_GM17 {
      G2Point H;
      G1Point Galpha;
      G2Point Hbeta;
      G1Point Ggamma;
      G2Point Hgamma;
      G1Point[] query;
  }

  Verification_Key_GM17 vk;

  function verify(uint256[] memory _proof, uint256[] memory _inputs, uint256[] memory _vk) public returns (bool result) {
      if (verificationCalculation(_proof, _inputs, _vk) == 0) {
          result = true;
      } else {
          result = false;
      }
  }

  function verificationCalculation(uint256[] memory _proof, uint256[] memory _inputs, uint256[] memory _vk) public returns (uint) {

      Proof_GM17 memory proof;
      G1Point memory vk_dot_inputs;

      vk_dot_inputs = G1Point(0, 0); //initialise

      proof.A = G1Point(_proof[0], _proof[1]);
      proof.B = G2Point([_proof[2], _proof[3]], [_proof[4], _proof[5]]);
      proof.C = G1Point(_proof[6], _proof[7]);

      vk.H = G2Point([_vk[0],_vk[1]],[_vk[2],_vk[3]]);
      vk.Galpha = G1Point(_vk[4],_vk[5]);
      vk.Hbeta = G2Point([_vk[6],_vk[7]],[_vk[8],_vk[9]]);
      vk.Ggamma = G1Point(_vk[10],_vk[11]);
      vk.Hgamma = G2Point([_vk[12],_vk[13]],[_vk[14],_vk[15]]);

      vk.query.length = (_vk.length - 16)/2;
      uint j = 0;
      for (uint i = 16; i < _vk.length; i+=2) {
        vk.query[j++] = G1Point(_vk[i], _vk[i+1]);
      }

      require(_inputs.length + 1 == vk.query.length, "Length of inputs[] or vk.query is incorrect!");

      for (uint i = 0; i < _inputs.length; i++)
          vk_dot_inputs = addition(vk_dot_inputs, scalar_mul(vk.query[i + 1], _inputs[i]));

      vk_dot_inputs = addition(vk_dot_inputs, vk.query[0]);

      /**
       * e(A*G^{alpha}, B*H^{beta}) = e(G^{alpha}, H^{beta}) * e(G^{psi}, H^{gamma})
       *                              * e(C, H)
       * where psi = \sum_{i=0}^l input_i pvk.query[i]
       */
      if (!pairingProd4(vk.Galpha, vk.Hbeta, vk_dot_inputs, vk.Hgamma, proof.C, vk.H, negate(addition(proof.A, vk.Galpha)), addition2(proof.B, vk.Hbeta))) {
          return 1;
      }


      /**
       * e(A, H^{gamma}) = e(G^{gamma}, B)
       */
      if (!pairingProd2(proof.A, vk.Hgamma, negate(vk.Ggamma), proof.B)) {
          return 2;
      }

      delete proof;
      delete vk.H;
      delete vk.Galpha;
      delete vk.Hbeta;
      delete vk.Ggamma;
      delete vk.Hgamma;
      delete vk.query;
      delete vk_dot_inputs;

      return 0;

  }
}
